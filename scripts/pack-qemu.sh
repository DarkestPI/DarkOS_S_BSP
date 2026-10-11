#!/bin/bash
# 用法: pack-qemu.sh qemu arm64 virt [--dry-run]
# 将已编译的三个组件组合为 U-Boot 可启动的 QEMU 镜像集合。
set -eo pipefail

# ========== 1. 加载配置并检查支持的目标 ==========
source "$(dirname "$0")/lib/bsp.sh"
bsp_load "${1:-}" "${2:-}" "${3:-}"
[ "$VENDOR/$SOC/$BOARD" = qemu/arm64/virt ] || bsp_die "此打包脚本支持 qemu arm64 virt"
if [ "${4:-}" = --dry-run ]; then
    echo "生成 boot.scr（使用实际 initramfs 大小）和 QEMU 镜像校验文件"
    exit
fi
# ========== 2. 检查组件镜像及 U-Boot 编译出的宿主工具 mkimage ==========
for image in u-boot.bin Image rootfs.cpio.gz; do
    [ -s "$IMAGES_DIR/$image" ] || bsp_die "缺少 $image，请先构建对应组件"
done
MKIMAGE="$OUTPUT_DIR/uboot/tools/mkimage"
[ -x "$MKIMAGE" ] || bsp_die "缺少 U-Boot mkimage"
# ========== 3. 检查加载区域容量，读取实际 initramfs 字节数 ==========
# 内核必须在 initramfs 地址之前结束；initramfs 预留容量为 64 MiB。
[ "$(stat -c %s "$IMAGES_DIR/Image")" -lt "$((BSP_QEMU_INITRD_ADDR - BSP_QEMU_KERNEL_ADDR))" ] || bsp_die "内核超出 QEMU 预留区域"
INITRD_SIZE=$(stat -c %s "$IMAGES_DIR/rootfs.cpio.gz")
[ "$INITRD_SIZE" -lt $((64 * 1024 * 1024)) ] || bsp_die "initramfs 超出预留的 64 MiB"
# ========== 4. 生成 boot.cmd，再添加 U-Boot 脚本镜像头 ==========
# booti 参数包含实际 initramfs 大小；fdtcontroladdr 保留给 U-Boot 启动时展开。
# QEMU 提供 DTB，脚本本身不生成或加载 RK3588 等物理板子的 DTB。
printf 'setenv bootargs %s\nbooti %s %s:0x%x ${fdtcontroladdr}\n' \
    "$BSP_KERNEL_CMDLINE" "$BSP_QEMU_KERNEL_ADDR" "$BSP_QEMU_INITRD_ADDR" "$INITRD_SIZE" > "$IMAGES_DIR/boot.cmd"
"$MKIMAGE" -A arm64 -T script -C none -n 'DarkOS QEMU ARM64' -d "$IMAGES_DIR/boot.cmd" "$IMAGES_DIR/boot.scr"
# ========== 5. 记录四个启动文件的 SHA256，供 run-qemu.sh 启动前检查 ==========
(cd "$IMAGES_DIR"; sha256sum u-boot.bin Image rootfs.cpio.gz boot.scr > SHA256SUMS)
echo "启动镜像: ${IMAGES_DIR#"$BSP_ROOT"/}"
