#!/bin/bash
# 用法: build-uboot.sh <vendor> <soc> <board> [build|clean|--dry-run]
# 保留原始 sources/u-boot，在当前板子的源码副本中应用补丁和编译。
set -eo pipefail

# ========== 1. 加载板级配置，处理当前组件的清理 ==========
source "$(dirname "$0")/lib/bsp.sh"
bsp_load "${1:-}" "${2:-}" "${3:-}"
bsp_action "${4:-build}"
BUILD_DIR="$OUTPUT_DIR/uboot"
if [ "$ACTION" = clean ]; then
    # boot.scr 与 U-Boot 配套，清理后需要重新构建并打包。
    rm -rf "$BUILD_DIR"
    rm -f "$IMAGES_DIR/u-boot.bin" "$IMAGES_DIR/u-boot.elf" "$IMAGES_DIR/boot.scr"
    exit
fi
# ========== 2. 检查工具链，收集补丁和配置片段 ==========
# 当前 ARM U-Boot 要求 GCC >= 10，可在板级配置中调整最低版本。
bsp_toolchain uboot "${BSP_UBOOT_MIN_GCC:-10.0.0}"
bsp_collect uboot
DEFCONFIG=${BSP_UBOOT_DEFCONFIG:-defconfig}
UBOOT_ARCH=${BSP_UBOOT_ARCH:-$ARCH}
# U-Boot 的 AArch64 实现位于 arch/arm，构建参数使用 ARCH=arm。
[ "$UBOOT_ARCH" != arm64 ] || UBOOT_ARCH=arm
echo "U-Boot: $TARGET / $DEFCONFIG / jobs=$JOBS"
if [ "$ACTION" = --dry-run ]; then
    # 检查并展示配置后结束，不拷贝源码、不执行 make。
    echo "补丁: ${#PATCH_FILES[@]}；配置片段: ${#CONFIG_FRAGMENTS[@]}"
    exit
fi
mkdir -p "$IMAGES_DIR" "$LOGS_DIR"
build_uboot() {
    # ========== 3. 准备源码副本，按 BSP 层级应用补丁 ==========
    # 已有副本会复用；更新原始源码或补丁后应先 clean uboot。
    bsp_copy_source "$BSP_ROOT/sources/u-boot" "$BUILD_DIR"
    bsp_apply_patches "$BUILD_DIR"
    if [ -n "${BSP_UBOOT_DEFCONFIG_FILE:-}" ]; then
        # 把板级 defconfig 放入副本的 configs，供 make 的配置目标读取。
        [ -f "$BSP_UBOOT_DEFCONFIG_FILE" ] || bsp_die "缺少 $BSP_UBOOT_DEFCONFIG_FILE"
        cp "$BSP_UBOOT_DEFCONFIG_FILE" "$BUILD_DIR/configs/$DEFCONFIG"
    fi
    local args=(-C "$BUILD_DIR" ARCH="$UBOOT_ARCH" CROSS_COMPILE="$CROSS_PREFIX")
    # ========== 4. 生成 .config，合并可选片段并补齐默认值 ==========
    make "${args[@]}" "$DEFCONFIG"
    if [ "${#CONFIG_FRAGMENTS[@]}" -gt 0 ]; then
        (cd "$BUILD_DIR"; scripts/kconfig/merge_config.sh -m .config "${CONFIG_FRAGMENTS[@]}")
        make "${args[@]}" olddefconfig
    fi
    # ========== 5. 编译并汇总二进制和 ELF 镜像 ==========
    # ELF 用于调试，u-boot.bin 用于 QEMU BIOS；mkimage 保留在副本/tools。
    make "${args[@]}" -j"$JOBS"
    bsp_copy_image "$BUILD_DIR/u-boot.bin"
    bsp_copy_image "$BUILD_DIR/u-boot" u-boot.elf
}
# 标准输出和错误输出一起记入日志，函数失败不会被 tee 的成功覆盖。
build_uboot 2>&1 | tee "$LOGS_DIR/uboot.log"
