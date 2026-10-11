#!/bin/bash
# 创建普通 SD 镜像文件，不访问或写入任何物理块设备。
# 用法: pack-rockchip.sh <vendor> <soc> <board> [--dry-run]
set -eo pipefail
source "$(dirname "$0")/lib/bsp.sh"
bsp_load "${1:-}" "${2:-}" "${3:-}"
[ "$VENDOR" = rockchip ] || bsp_die "此打包后端用于 Rockchip"
case "${4:-}" in ''|--dry-run) ;; *) bsp_die "未知打包操作 $4" ;; esac

LOADER=${BSP_BOOTLOADER_IMAGE:-u-boot-rockchip.bin}
DTB=${BSP_BOOT_DTB:-${BSP_DTS_NAME:-}.dtb}
LOADER_SECTOR=${BSP_BOOTLOADER_OFFSET_SECTORS:-64}
BOOT_START=${BSP_BOOT_PARTITION_START_MIB:-16}
BOOT_SIZE=${BSP_BOOT_PARTITION_SIZE_MIB:-128}
IMAGE_SIZE=${BSP_IMAGE_SIZE_MIB:-512}
ROOT_UUID=${BSP_ROOTFS_PARTUUID:-}
for name in LOADER DTB; do
    [[ "${!name}" =~ ^[a-zA-Z0-9_.-]+$ ]] || bsp_die "$name 必须是镜像文件名"
done
for name in LOADER_SECTOR BOOT_START BOOT_SIZE IMAGE_SIZE; do
    [[ "${!name}" =~ ^[1-9][0-9]*$ ]] || bsp_die "$name 必须是正整数"
done
[[ "$ROOT_UUID" =~ ^[[:xdigit:]]{8}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{4}-[[:xdigit:]]{12}$ ]] || bsp_die "需要合法的 BSP_ROOTFS_PARTUUID"
MIB=$((1024 * 1024))
BOOT_SECTOR=$((BOOT_START * 2048))
BOOT_SECTORS=$((BOOT_SIZE * 2048))
ROOT_SECTOR=$((BOOT_SECTOR + BOOT_SECTORS))
# 给备份 GPT 预留最后 34 个扇区。
ROOT_SECTORS=$((IMAGE_SIZE * 2048 - ROOT_SECTOR - 34))
[ "$ROOT_SECTORS" -gt 0 ] || bsp_die "镜像大小不足以容纳分区"
[ "$LOADER_SECTOR" -ge 34 ] && [ "$LOADER_SECTOR" -lt "$BOOT_SECTOR" ] || bsp_die "BootROM 镜像位置与 GPT 或 boot 分区重叠"
CMDLINE=${BSP_KERNEL_CMDLINE:-rootwait rw}
[[ " $CMDLINE " != *" root="* ]] || bsp_die "BSP_KERNEL_CMDLINE 中的 root= 由打包器根据 PARTUUID 生成"
CMDLINE="$CMDLINE root=PARTUUID=$ROOT_UUID"
echo "Rockchip SD 镜像: $TARGET / ${IMAGE_SIZE} MiB"
echo "启动固件: $LOADER / LBA $LOADER_SECTOR"
echo "boot: ${BOOT_START} MiB 起 / ${BOOT_SIZE} MiB；rootfs: $ROOT_SECTOR 扇区起"
echo "设备树: $DTB"
echo "内核参数: $CMDLINE"
if [ "${4:-}" = --dry-run ]; then
    echo "将生成 images/sdcard.img、boot.ext4、extlinux.conf 和 SHA256SUMS"
    exit
fi

for tool in sfdisk mkfs.ext4 truncate dd; do
    command -v "$tool" >/dev/null || bsp_die "缺少打包工具 $tool"
done
for file in "$LOADER" Image "$DTB" rootfs.ext4; do
    [ -s "$IMAGES_DIR/$file" ] || bsp_die "缺少 $file，请先构建对应组件"
done
LOADER_BYTES=$(stat -Lc %s "$IMAGES_DIR/$LOADER")
ROOT_BYTES=$(stat -Lc %s "$IMAGES_DIR/rootfs.ext4")
[ "$((LOADER_SECTOR * 512 + LOADER_BYTES))" -le "$((BOOT_SECTOR * 512))" ] || bsp_die "启动固件超出 boot 前的保留区域"
[ "$ROOT_BYTES" -le "$((ROOT_SECTORS * 512))" ] || bsp_die "rootfs.ext4 超出 rootfs 分区"

# 所有工具只操作新建临时目录中的普通文件，完成后再替换正式产物。
PACK_DIR=$(mktemp -d "$OUTPUT_DIR/.pack-rockchip.XXXXXX")
trap 'rm -rf "$PACK_DIR"' EXIT
mkdir -p "$PACK_DIR/boot/extlinux"
cp "$IMAGES_DIR/Image" "$IMAGES_DIR/$DTB" "$PACK_DIR/boot/"
cat > "$PACK_DIR/boot/extlinux/extlinux.conf" <<EOF
DEFAULT darkos
TIMEOUT 30
MENU TITLE DarkOS $BSP_BOARD_NAME

LABEL darkos
    MENU LABEL DarkOS
    LINUX /Image
    FDT /$DTB
    APPEND $CMDLINE
EOF
truncate -s "$((BOOT_SIZE * MIB))" "$PACK_DIR/boot.ext4"
mkfs.ext4 -q -F -L boot -O ^64bit,^metadata_csum \
    -E lazy_itable_init=0,lazy_journal_init=0 \
    -d "$PACK_DIR/boot" "$PACK_DIR/boot.ext4"

truncate -s "$((IMAGE_SIZE * MIB))" "$PACK_DIR/sdcard.img"
sfdisk --no-reread --no-tell-kernel "$PACK_DIR/sdcard.img" > "$PACK_DIR/partition.log" <<EOF
label: gpt
unit: sectors

start=$BOOT_SECTOR, size=$BOOT_SECTORS, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name="boot", attrs="LegacyBIOSBootable"
start=$ROOT_SECTOR, size=$ROOT_SECTORS, type=0FC63DAF-8483-4772-8E79-3D69D8477DE4, name="rootfs", uuid=$ROOT_UUID
EOF
dd if="$IMAGES_DIR/$LOADER" of="$PACK_DIR/sdcard.img" bs=512 \
    seek="$LOADER_SECTOR" conv=notrunc status=none
dd if="$PACK_DIR/boot.ext4" of="$PACK_DIR/sdcard.img" bs=512 \
    seek="$BOOT_SECTOR" conv=notrunc status=none
dd if="$IMAGES_DIR/rootfs.ext4" of="$PACK_DIR/sdcard.img" bs=512 \
    seek="$ROOT_SECTOR" conv=notrunc status=none

# 保存可审阅的启动配置和分区表，文件系统镜像保留为独立构建产物。
mv "$PACK_DIR/sdcard.img" "$IMAGES_DIR/sdcard.img"
mv "$PACK_DIR/boot.ext4" "$IMAGES_DIR/boot.ext4"
cp "$PACK_DIR/boot/extlinux/extlinux.conf" "$IMAGES_DIR/extlinux.conf"
sfdisk --json "$IMAGES_DIR/sdcard.img" > "$IMAGES_DIR/partitions.json"
(cd "$IMAGES_DIR"; sha256sum "$LOADER" Image "$DTB" rootfs.ext4 boot.ext4 sdcard.img > SHA256SUMS)
echo "启动镜像: ${IMAGES_DIR#"$BSP_ROOT"/}/sdcard.img"
