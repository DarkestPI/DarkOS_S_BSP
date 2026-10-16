#!/bin/bash
# 用法: run-qemu.sh [qemu arm64 virt] [--dry-run]
# 使用已打包镜像启动 QEMU；此脚本不执行编译。
set -eo pipefail

# ========== 1. 加载 QEMU 板级配置 ==========
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "$SCRIPT_DIR/../lib/bsp.sh"
bsp_load "${1:-qemu}" "${2:-arm64}" "${3:-virt}"
[ "$VENDOR/$SOC/$BOARD" = qemu/arm64/virt ] || bsp_die "此启动脚本支持 qemu arm64 virt"
# ========== 2. 读取运行参数覆盖，检查内存和 CPU 数量 ==========
# 256 MiB 是当前内存布局允许的最小值；CPU 数量对应 CONFIG_NR_CPUS=4。
MEMORY=${QEMU_MEMORY:-$BSP_QEMU_MEMORY}
CPUS=${QEMU_CPUS:-$BSP_QEMU_CPUS}
[[ "$MEMORY" =~ ^[0-9]+$ ]] && [ "$MEMORY" -ge 256 ] || bsp_die "QEMU_MEMORY 至少为 256（MiB）"
[[ "$CPUS" =~ ^[1-4]$ ]] || bsp_die "QEMU_CPUS 范围为 1 到 4"
# ========== 3. 组装 QEMU 启动命令 ==========
# -bios 启动 U-Boot；generic loader 按板级地址载入脚本、内核和 initramfs。
# -nographic 使用串口/monitor 复用，支持 Ctrl+A X 退出。
# user 网络与 virtio 网卡供 guest 获取 DHCP 地址，无需配置宿主 tap 设备。
ARGS=("${QEMU_BINARY:-$BSP_QEMU_BINARY}" -machine virt -cpu "${QEMU_CPU:-$BSP_QEMU_CPU}"
    -m "$MEMORY" -smp "$CPUS" -nographic
    -bios "$IMAGES_DIR/u-boot.bin"
    -device "loader,file=$IMAGES_DIR/boot.scr,addr=$BSP_QEMU_SCRIPT_ADDR,force-raw=on"
    -device "loader,file=$IMAGES_DIR/Image,addr=$BSP_QEMU_KERNEL_ADDR,force-raw=on"
    -device "loader,file=$IMAGES_DIR/rootfs.cpio.gz,addr=$BSP_QEMU_INITRD_ADDR,force-raw=on"
    -netdev user,id=net0 -device virtio-net-device,netdev=net0)
# ========== 4. dry-run 展示命令；实际启动前检查程序、镜像和校验值 ==========
if [ "${4:-}" = --dry-run ]; then printf '%q ' "${ARGS[@]}"; echo; exit; fi
command -v "${ARGS[0]}" >/dev/null || bsp_die "找不到 ${ARGS[0]}"
for image in u-boot.bin Image rootfs.cpio.gz boot.scr; do
    [ -s "$IMAGES_DIR/$image" ] || bsp_die "缺少 $image，请先执行 build.sh $VENDOR $SOC $BOARD all"
done
(cd "$IMAGES_DIR"; sha256sum --status -c SHA256SUMS) || bsp_die "镜像已改变或未打包，请执行 build.sh $VENDOR $SOC $BOARD pack"
# ========== 5. 以 QEMU 替换当前 shell，保持信号和退出码直接传递 ==========
exec "${ARGS[@]}"
