#!/bin/bash
# 用法: build-kernel.sh <vendor> <soc> <board> [build|clean] [--full|--incremental] [--dry-run]
# 每块板使用独立源码副本；共享 sources/linux 始终作为输入。
set -eo pipefail

source "$(dirname "$0")/lib/bsp.sh"
bsp_load "${1:-}" "${2:-}" "${3:-}"
bsp_action "${@:4}"
case "$ACTION" in build|clean) ;; *) bsp_die "内核不支持 $ACTION" ;; esac
bsp_source kernel
SRC_KERNEL="$SOURCE_DIR"
BUILD_DIR="$OUTPUT_DIR/kernel"
LOG_FILE="$LOGS_DIR/kernel.log"

clean_kernel() {
    rm -rf "$BUILD_DIR"
    rm -f "$IMAGES_DIR/"Image* "$IMAGES_DIR/zImage" "$IMAGES_DIR/"*.dtb "$IMAGES_DIR/boot.scr"
}
if [ "$ACTION" = clean ]; then
    if [ "$DRY_RUN" = y ]; then echo "将清理内核: $BUILD_DIR"; else clean_kernel; fi
    exit
fi
[ -d "$SRC_KERNEL" ] || bsp_die "找不到内核源码 $SRC_KERNEL"
DEFCONFIG=${BSP_DEFCONFIG:-defconfig}
DEFCONFIG_FILE=${BSP_DEFCONFIG_FILE:-$SRC_KERNEL/arch/$ARCH/configs/$DEFCONFIG}
[[ "$DEFCONFIG_FILE" = /* ]] || DEFCONFIG_FILE="$BSP_ROOT/$DEFCONFIG_FILE"
if [ -x "$SRC_KERNEL/scripts/min-tool-version.sh" ]; then
    MIN_GCC=$(ARCH="$ARCH" "$SRC_KERNEL/scripts/min-tool-version.sh" gcc)
else
    MIN_GCC=${BSP_KERNEL_MIN_GCC:-8.1.0}
fi
bsp_toolchain kernel "$MIN_GCC"
CROSS_COMPILE=$CROSS_PREFIX
bsp_collect linux
DTS_SOURCE=${BSP_DTS_DIR-$BOARD_DIR/dts}
if [ -n "$DTS_SOURCE" ]; then
    [[ "$DTS_SOURCE" = /* ]] || DTS_SOURCE="$BSP_ROOT/$DTS_SOURCE"
    # 缺省 dts 目录允许不存在；显式配置的目录必须有效。
    if [[ -v BSP_DTS_DIR ]]; then [ -d "$DTS_SOURCE" ] || bsp_die "缺少板级 DTS 目录 $DTS_SOURCE"; fi
fi
read -r -a BUILD_TARGETS <<< "${BSP_KERNEL_TARGETS:-}"
echo "Kernel: $TARGET / $DEFCONFIG / arch=$ARCH / jobs=$JOBS"
echo "源码: $SRC_KERNEL"
echo "补丁: ${#PATCH_FILES[@]}；配置片段: ${#CONFIG_FRAGMENTS[@]}"
for file in "${PATCH_FILES[@]}"; do echo "  patch: $file"; done
for file in "${CONFIG_FRAGMENTS[@]}"; do echo "  fragment: $file"; done

PLAN_ARGS=(--value arch "$ARCH" --value defconfig "$DEFCONFIG"
    --input defconfig-file "$DEFCONFIG_FILE" --value toolchain "$(bsp_toolchain_identity)"
    --value compiler-prefix "$CROSS_PREFIX" --value targets "${BUILD_TARGETS[*]}"
    --value device-tree "${BSP_DTS_NAME:-}" --update-tree board-dts "$DTS_SOURCE"
    --value build-flags "${KCFLAGS:-}|${KCPPFLAGS:-}|${LDFLAGS:-}|${HOSTCC:-}|${HOSTCFLAGS:-}|${LLVM:-}|${LLVM_IAS:-}"
    --input build-script "$BSP_ROOT/scripts/build-kernel.sh"
    --input build-library "$BSP_ROOT/scripts/lib/bsp.sh"
    --input build-planner "$BSP_ROOT/scripts/lib/build-state.py"
    --effective-config "$BUILD_DIR/.config")
for index in "${!PATCH_FILES[@]}"; do PLAN_ARGS+=(--input "patch-$index" "${PATCH_FILES[$index]}"); done
for index in "${!CONFIG_FRAGMENTS[@]}"; do PLAN_ARGS+=(--input "fragment-$index" "${CONFIG_FRAGMENTS[$index]}"); done
[ "${#PATCH_FILES[@]}" -eq 0 ] || PLAN_ARGS+=(--patched)
bsp_build_plan kernel "$SRC_KERNEL" "$BUILD_DIR" "${PLAN_ARGS[@]}"
[ "$DRY_RUN" != y ] || exit 0
[ -f "$DEFCONFIG_FILE" ] || bsp_die "找不到内核配置 $DEFCONFIG_FILE"
[ "$BUILD_MODE" != full ] || clean_kernel
mkdir -p "$IMAGES_DIR" "$LOGS_DIR"
bsp_build_begin

build_kernel() {
    bsp_copy_source "$SRC_KERNEL" "$BUILD_DIR"
    bsp_apply_patches "$BUILD_DIR"
    # DTS 修改触发相应 dtb 重编，未改动的文件保持时间戳。
    if [ -n "$DTS_SOURCE" ] && [ -d "$DTS_SOURCE" ]; then
        local dts destination dts_dest="$BUILD_DIR/arch/$ARCH/boot/dts/$VENDOR"
        mkdir -p "$dts_dest"
        shopt -s nullglob
        for dts in "$DTS_SOURCE/"*.dts "$DTS_SOURCE/"*.dtsi; do
            [[ "$dts" = *-u-boot.dtsi ]] && continue
            destination="$dts_dest/$(basename "$dts")"
            cmp -s "$dts" "$destination" || cp "$dts" "$destination"
        done
        shopt -u nullglob
    fi
    local args=(-C "$BUILD_DIR" ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE")
    if [ "$BUILD_MODE" = full ] || [ ! -f "$BUILD_DIR/.config" ]; then
        if [ -n "${BSP_DEFCONFIG_FILE:-}" ]; then
            mkdir -p "$BUILD_DIR/arch/$ARCH/configs"
            cp "$DEFCONFIG_FILE" "$BUILD_DIR/arch/$ARCH/configs/$DEFCONFIG"
        fi
        make "${args[@]}" "$DEFCONFIG"
        if [ "${#CONFIG_FRAGMENTS[@]}" -gt 0 ]; then
            (cd "$BUILD_DIR"; scripts/kconfig/merge_config.sh -m -O "$BUILD_DIR" .config "${CONFIG_FRAGMENTS[@]}")
        fi
        make "${args[@]}" olddefconfig
    fi
    make "${args[@]}" -j"$JOBS" "${BUILD_TARGETS[@]}"
    local image
    case "$ARCH" in
        arm64)
            bsp_copy_image "$BUILD_DIR/arch/arm64/boot/Image"
            shopt -s nullglob
            for image in "$BUILD_DIR/arch/arm64/boot/Image."*; do bsp_copy_image "$image"; done
            shopt -u nullglob
            if [ -n "${BSP_DTS_NAME:-}" ]; then
                bsp_copy_image "$BUILD_DIR/arch/arm64/boot/dts/$VENDOR/$BSP_DTS_NAME.dtb"
            fi ;;
        arm)
            bsp_copy_image "$BUILD_DIR/arch/arm/boot/zImage"
            shopt -s nullglob
            for image in "$BUILD_DIR/arch/arm/boot/dts/"*.dtb; do bsp_copy_image "$image"; done
            shopt -u nullglob ;;
        riscv) bsp_copy_image "$BUILD_DIR/arch/riscv/boot/Image" ;;
        *) bsp_die "没有为 ARCH=$ARCH 定义内核镜像汇总规则" ;;
    esac
    bsp_build_commit
}
build_kernel 2>&1 | tee "$LOG_FILE"
echo "内核构建完成: $IMAGES_DIR"
