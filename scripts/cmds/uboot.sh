#!/bin/bash
# 用法: build-uboot.sh <vendor> <soc> <board> [build|clean] [--full|--incremental] [--dry-run]
# 保留原始 sources/u-boot，在当前板子的源码副本中应用补丁和编译。
set -eo pipefail

# ========== 1. 加载板级配置，处理当前组件的清理 ==========
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "$SCRIPT_DIR/../lib/bsp.sh"
bsp_load "${1:-}" "${2:-}" "${3:-}"
bsp_action "${@:4}"
case "$ACTION" in build|clean) ;; *) bsp_die "U-Boot 不支持 $ACTION" ;; esac
bsp_source uboot
SRC_UBOOT="$SOURCE_DIR"
BUILD_DIR="$OUTPUT_DIR/uboot"
clean_uboot() {
    # boot.scr 与 U-Boot 配套，清理后需要重新构建并打包。
    local image extra_images=()
    if [ -f "$BUILD_DIR/.darkos-images" ]; then
        while IFS= read -r image; do
            [ "$image" = "$(basename "$image")" ] || bsp_die "无效的产物记录 $image"
            rm -f "$IMAGES_DIR/$image"
        done < "$BUILD_DIR/.darkos-images"
    fi
    rm -f "$IMAGES_DIR/u-boot.bin" "$IMAGES_DIR/u-boot.elf" "$IMAGES_DIR/boot.scr"
    read -r -a extra_images <<< "${BSP_UBOOT_EXTRA_IMAGES:-}"
    for image in "${extra_images[@]}"; do
        [ "$image" = "$(basename "$image")" ] || bsp_die "U-Boot 产物必须是文件名: $image"
        rm -f "$IMAGES_DIR/$image"
    done
    rm -rf "$BUILD_DIR"
}
if [ "$ACTION" = clean ]; then
    if [ "$DRY_RUN" = y ]; then echo "将清理 U-Boot: $BUILD_DIR"; else clean_uboot; fi
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
echo "源码: $SRC_UBOOT"
BL31_FILE=${BL31:-${BSP_UBOOT_BL31:-}}
TPL_FILE=${ROCKCHIP_TPL:-${BSP_UBOOT_TPL:-}}
for name in BL31_FILE TPL_FILE; do
    if [ -n "${!name}" ] && [[ "${!name}" != /* ]]; then
        printf -v "$name" '%s' "$BSP_ROOT/${!name}"
    fi
done
printf 'BL31: %s\nROCKCHIP_TPL: %s\n' "${BL31_FILE:-未指定}" "${TPL_FILE:-未指定}"
# 全量输入包括配置、补丁、编译器、固件；DTS 内容修改可以增量重编。
DEFCONFIG_FILE=${BSP_UBOOT_DEFCONFIG_FILE:-$SRC_UBOOT/configs/$DEFCONFIG}
[[ "$DEFCONFIG_FILE" = /* ]] || DEFCONFIG_FILE="$BSP_ROOT/$DEFCONFIG_FILE"
DTS_SOURCE=${BSP_UBOOT_DTS_DIR:-}
if [ -n "$DTS_SOURCE" ]; then
    [[ "$DTS_SOURCE" = /* ]] || DTS_SOURCE="$BSP_ROOT/$DTS_SOURCE"
    [ -d "$DTS_SOURCE" ] || bsp_die "缺少 U-Boot 板级设备树目录 $DTS_SOURCE"
fi
PLAN_ARGS=(--value arch "$UBOOT_ARCH" --value defconfig "$DEFCONFIG"
    --input defconfig-file "$DEFCONFIG_FILE"
    --value toolchain "$(bsp_toolchain_identity)" --value compiler-prefix "$CROSS_PREFIX"
    --value device-tree "${BSP_UBOOT_DTS_NAME:-}" --update-tree board-dts "$DTS_SOURCE"
    --input BL31 "$BL31_FILE" --input ROCKCHIP_TPL "$TPL_FILE"
    --value extra-images "${BSP_UBOOT_EXTRA_IMAGES:-}"
    --value build-flags "${KCFLAGS:-}|${KCPPFLAGS:-}|${LDFLAGS:-}|${HOSTCC:-}|${HOSTCFLAGS:-}"
    --input build-script "$SCRIPT_DIR/uboot.sh"
    --input build-library "$BSP_ROOT/scripts/lib/bsp.sh"
    --input build-planner "$BSP_ROOT/scripts/lib/build-state.py"
    --effective-config "$BUILD_DIR/.config")
for index in "${!PATCH_FILES[@]}"; do PLAN_ARGS+=(--input "patch-$index" "${PATCH_FILES[$index]}"); done
for index in "${!CONFIG_FRAGMENTS[@]}"; do PLAN_ARGS+=(--input "fragment-$index" "${CONFIG_FRAGMENTS[$index]}"); done
[ "${#PATCH_FILES[@]}" -eq 0 ] || PLAN_ARGS+=(--patched)
bsp_build_plan uboot "$SRC_UBOOT" "$BUILD_DIR" "${PLAN_ARGS[@]}"
if [ "$DRY_RUN" = y ]; then
    # 检查并展示配置后结束，不拷贝源码、不执行 make。
    echo "补丁: ${#PATCH_FILES[@]}；配置片段: ${#CONFIG_FRAGMENTS[@]}"
    exit
fi
# 在创建副本前校验固件；可用环境变量选择自己构建的 BL31 或匹配的 DDR。
check_firmware() {
    local name=$1 required=$2 file=$3 expected=$4 actual
    if [ "$required" = y ] || [ -n "$file" ]; then
        [ -n "$file" ] && [ -s "$file" ] || bsp_die "缺少 $name 固件: ${file:-未指定}；请初始化 rkbin 或设置 $name"
        if [ -n "$expected" ]; then
            actual=$(sha256sum "$file")
            [ "${actual%% *}" = "$expected" ] || bsp_die "$name 固件校验失败: $file"
        fi
    fi
}
BL31_SHA=${BSP_UBOOT_BL31_SHA256:-}
TPL_SHA=${BSP_UBOOT_TPL_SHA256:-}
# 显式选择的自建固件不套用发行二进制的校验值。
[ -z "${BL31:-}" ] || BL31_SHA=
[ -z "${ROCKCHIP_TPL:-}" ] || TPL_SHA=
check_firmware BL31 "${BSP_UBOOT_REQUIRE_BL31:-n}" "$BL31_FILE" "$BL31_SHA"
check_firmware ROCKCHIP_TPL "${BSP_UBOOT_REQUIRE_TPL:-n}" "$TPL_FILE" "$TPL_SHA"
[ -d "$SRC_UBOOT" ] || bsp_die "找不到 U-Boot 源码 $SRC_UBOOT"
bsp_host_tools
[ "$BUILD_MODE" != full ] || clean_uboot
mkdir -p "$IMAGES_DIR" "$LOGS_DIR"
bsp_build_begin
build_uboot() {
    # ========== 3. 准备源码副本，按 BSP 层级应用补丁 ==========
    # 增量时同步工作区改动；全量时创建干净副本并重新应用 BSP 补丁。
    bsp_copy_source "$SRC_UBOOT" "$BUILD_DIR"
    bsp_apply_patches "$BUILD_DIR"
    if [ -n "${BSP_UBOOT_DEFCONFIG_FILE:-}" ]; then
        # 把板级 defconfig 放入副本的 configs，供 make 的配置目标读取。
        [ -f "$DEFCONFIG_FILE" ] || bsp_die "缺少 $DEFCONFIG_FILE"
        mkdir -p "$BUILD_DIR/configs"
        cp "$DEFCONFIG_FILE" "$BUILD_DIR/configs/$DEFCONFIG"
    fi
    if [ -n "$DTS_SOURCE" ]; then
        local dts destination
        mkdir -p "$BUILD_DIR/arch/arm/dts"
        shopt -s nullglob
        for dts in "$DTS_SOURCE/"*.dts "$DTS_SOURCE/"*.dtsi; do
            destination="$BUILD_DIR/arch/arm/dts/$(basename "$dts")"
            cmp -s "$dts" "$destination" || cp "$dts" "$destination"
        done
        shopt -u nullglob
    fi
    local args=(-C "$BUILD_DIR" ARCH="$UBOOT_ARCH" CROSS_COMPILE="$CROSS_PREFIX")
    [ -z "${BSP_UBOOT_DTS_NAME:-}" ] || args+=("DEVICE_TREE=$BSP_UBOOT_DTS_NAME")
    [ -z "$BL31_FILE" ] || args+=("BL31=$BL31_FILE")
    [ -z "$TPL_FILE" ] || args+=("ROCKCHIP_TPL=$TPL_FILE")
    # ========== 4. 生成 .config，合并可选片段并补齐默认值 ==========
    if [ "$BUILD_MODE" = full ] || [ ! -f "$BUILD_DIR/.config" ]; then
        make "${args[@]}" "$DEFCONFIG"
        if [ "${#CONFIG_FRAGMENTS[@]}" -gt 0 ]; then
            (cd "$BUILD_DIR"; scripts/kconfig/merge_config.sh -m .config "${CONFIG_FRAGMENTS[@]}")
            make "${args[@]}" olddefconfig
        fi
    fi
    # ========== 5. 编译并汇总二进制和 ELF 镜像 ==========
    # ELF 用于调试，u-boot.bin 用于 QEMU BIOS；mkimage 保留在副本/tools。
    make "${args[@]}" -j"$JOBS"
    bsp_copy_image "$BUILD_DIR/u-boot.bin"
    bsp_copy_image "$BUILD_DIR/u-boot" u-boot.elf
    local image extra_images=()
    read -r -a extra_images <<< "${BSP_UBOOT_EXTRA_IMAGES:-}"
    for image in "${extra_images[@]}"; do
        [ "$image" = "$(basename "$image")" ] || bsp_die "U-Boot 产物必须是文件名: $image"
        bsp_copy_image "$BUILD_DIR/$image"
    done
    printf '%s\n' u-boot.bin u-boot.elf "${extra_images[@]}" > "$BUILD_DIR/.darkos-images"
    bsp_build_commit
}
# 标准输出和错误输出一起记入日志，函数失败不会被 tee 的成功覆盖。
build_uboot 2>&1 | tee "$LOGS_DIR/uboot.log"
