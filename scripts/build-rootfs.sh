#!/bin/bash
# 用法: build-rootfs.sh <vendor> <soc> <board> [build|clean|--dry-run|configure|menuconfig]
# 直接使用 sources/buildroot，通过 O= 将构建过程与产物写入目标/rootfs。
set -eo pipefail

# ========== 1. 加载配置，处理当前 rootfs 组件的清理 ==========
source "$(dirname "$0")/lib/bsp.sh"
bsp_load "${1:-}" "${2:-}" "${3:-}"
ACTION=${4:-build}
case "$ACTION" in build|clean|--dry-run|configure|menuconfig) ;; *) bsp_die "不支持的 rootfs 操作 $ACTION" ;; esac
BUILD_DIR="$OUTPUT_DIR/rootfs"
bsp_source rootfs
SRC_BUILDROOT="$SOURCE_DIR"
if [ "$ACTION" = clean ]; then
    # 删除当前 rootfs 构建目录和汇总镜像，保留共享下载缓存及其他组件。
    rm -rf "$BUILD_DIR"
    rm -f "$IMAGES_DIR/"rootfs.* "$IMAGES_DIR/boot.scr"
    exit
fi
echo "Buildroot: $TARGET / ${BSP_BUILDROOT_DEFCONFIG:-未指定} / jobs=$JOBS"
# ========== 2. 检查自动配置模式的工具链，处理 dry-run ==========
# 自动模式用于 QEMU 外部 glibc 工具链；其他平台可使用自身 defconfig。
if [ "${BSP_ROOTFS_EXTERNAL_AUTO:-n}" = y ]; then bsp_toolchain rootfs "${BSP_ROOTFS_MIN_GCC:-4.8.0}"; fi
if [ "$ACTION" = --dry-run ]; then
    echo "链接各 BSP 层到 ${BR2_EXT#"$BSP_ROOT"/}；构建 rootfs，内核单独构建"
    exit
fi
# ========== 3. 准备分层链接和 Buildroot 构建参数 ==========
# 下载缓存可由 BR2_DL_DIR 指定；默认在 output/downloads 中供所有目标复用。
bsp_check_rootfs_source "$SRC_BUILDROOT" "$BUILD_DIR"
mkdir -p "$BUILD_DIR" "$IMAGES_DIR" "$LOGS_DIR" "$BSP_ROOT/output/downloads"
bsp_prepare_external
export GIT_OPTIONAL_LOCKS=0
ARGS=(-C "$SRC_BUILDROOT" O="$BUILD_DIR" BR2_EXTERNAL="$BR2_EXT"
    DARKOS_BSP_TARGET="$TARGET" BR2_DL_DIR="${BR2_DL_DIR:-$BSP_ROOT/output/downloads}")
configure_rootfs() {
    # ========== 4. 从板级模板生成本机可用的 rootfs.defconfig ==========
    # 生成文件位于 output，板级模板保留在 boards 中维护。
    local base="$BR2_EXT/configs/${BSP_BUILDROOT_DEFCONFIG:-${TARGET}_defconfig}"
    local generated="$OUTPUT_DIR/rootfs.defconfig" gcc_path toolchain_path prefix major code headers capabilities libc_path sysroot
    cp "$base" "$generated"
    if [ "${BSP_ROOTFS_EXTERNAL_AUTO:-n}" = y ]; then
        # 4.1 从编译器实际位置提取工具链根目录、程序前缀及 GCC 主版本。
        gcc_path=$(command -v "${CROSS_PREFIX}gcc")
        toolchain_path=$(cd "$(dirname "$gcc_path")/.." && pwd)
        prefix=$(basename "${CROSS_PREFIX%-}")
        major=${CROSS_VERSION%%.*}
        # 4.2 检查 libc 并读取工具链自带的 Linux headers 版本。
        # headers 版本用于构建用户态，与当前运行内核版本可以不同。
        printf '#include <features.h>\n' | "${CROSS_PREFIX}gcc" -E -dM -x c - | \
            awk '$2 == "__GLIBC__" {found=1} END {exit !found}' || bsp_die "自动配置目前支持 glibc 工具链；其他 libc 请编写对应的 Buildroot defconfig"
        code=$(printf '#include <linux/version.h>\n' | "${CROSS_PREFIX}gcc" -E -dM -x c - | awk '$2 == "LINUX_VERSION_CODE" {print $3}')
        [[ "$code" =~ ^[0-9]+$ ]] || bsp_die "无法检测外部工具链的 Linux headers"
        headers="$((code >> 16))_$(((code >> 8) & 255))"
        grep -q "^config BR2_TOOLCHAIN_EXTERNAL_HEADERS_$headers$" "$SRC_BUILDROOT/toolchain/toolchain-external/toolchain-external-custom/Config.in.options" || bsp_die "Buildroot 不支持 headers $headers"
        # 4.3 用实际版本替换模板声明，避免 Buildroot 的工具链检查拒绝构建。
        sed -i '/^BR2_TOOLCHAIN_EXTERNAL_GCC_[0-9]/d; /^BR2_TOOLCHAIN_EXTERNAL_HEADERS_[0-9]/d' "$generated"
        printf '\nBR2_TOOLCHAIN_EXTERNAL_PATH="%s"\nBR2_TOOLCHAIN_EXTERNAL_CUSTOM_PREFIX="%s"\nBR2_TOOLCHAIN_EXTERNAL_GCC_%s=y\nBR2_TOOLCHAIN_EXTERNAL_HEADERS_%s=y\n' \
            "$toolchain_path" "$prefix" "$major" "$headers" >> "$generated"
        sed -i '/^BR2_TOOLCHAIN_EXTERNAL_\(CXX\|FORTRAN\|DLANG\|OPENMP\)=/d' "$generated"
        # 4.4 按 Buildroot 的 libc.a 路径规则定位 sysroot，检测原生 RPC。
        # 显式写入禁用项，覆盖 glibc 工具链默认启用 RPC 的 Kconfig 行为。
        libc_path=$("${CROSS_PREFIX}gcc" -print-file-name=libc.a)
        libc_path=$(readlink -f "$libc_path") || bsp_die "无法定位外部工具链的 libc.a"
        [ -f "$libc_path" ] || bsp_die "外部工具链缺少 libc.a，无法检测 RPC 支持"
        sysroot=$(printf '%s\n' "$libc_path" | sed -E 's:/(usr/)?lib(32|64)?([^/]*)?/([^/]*/)?libc\.a$:/:')
        [ "$sysroot" != "$libc_path" ] && [ -d "$sysroot/usr/include" ] || bsp_die "无法定位外部工具链的 sysroot headers"
        sed -i '/^BR2_TOOLCHAIN_EXTERNAL_INET_RPC=/d; /^# BR2_TOOLCHAIN_EXTERNAL_INET_RPC is not set$/d' "$generated"
        if [ -f "$sysroot/usr/include/rpc/rpc.h" ]; then
            printf 'BR2_TOOLCHAIN_EXTERNAL_INET_RPC=y\n' >> "$generated"
        else
            printf '# BR2_TOOLCHAIN_EXTERNAL_INET_RPC is not set\n' >> "$generated"
        fi
        # 4.5 按真实能力声明 C++、Fortran、D 和 OpenMP。
        # 探测只编译小程序，不运行目标架构程序，结束后删除临时文件。
        if "${CROSS_PREFIX}g++" -v >/dev/null 2>&1; then
            printf 'BR2_TOOLCHAIN_EXTERNAL_CXX=y\n' >> "$generated"
        fi
        capabilities=$(mktemp -d "$OUTPUT_DIR/.toolchain-test.XXXXXX")
        if printf 'program hello\nprint *, "hello"\nend program hello\n' | \
            "${CROSS_PREFIX}gfortran" -x f95 -ffree-form -o "$capabilities/fortran" - >/dev/null 2>&1; then
            printf 'BR2_TOOLCHAIN_EXTERNAL_FORTRAN=y\n' >> "$generated"
        fi
        if printf 'import std.stdio; void main() { writeln("hello"); }\n' | \
            "${CROSS_PREFIX}gdc" -x d -o "$capabilities/dlang" - >/dev/null 2>&1; then
            printf 'BR2_TOOLCHAIN_EXTERNAL_DLANG=y\n' >> "$generated"
        fi
        if printf '#include <omp.h>\nint main(void) { return omp_get_thread_num(); }\n' | \
            "${CROSS_PREFIX}gcc" -fopenmp -x c -o "$capabilities/openmp" - >/dev/null 2>&1; then
            printf 'BR2_TOOLCHAIN_EXTERNAL_OPENMP=y\n' >> "$generated"
        fi
        rm -rf "$capabilities"
    fi
    if [ "${#ROOTFS_OVERLAYS[@]}" -gt 0 ]; then
        # 4.6 按 common -> vendor -> SoC -> board 顺序叠加 rootfs 文件。
        printf 'BR2_ROOTFS_OVERLAY="%s"\n' "${ROOTFS_OVERLAYS[*]}" >> "$generated"
    fi
    # ========== 5. 按需加载配置，保留未改模板时的 menuconfig 修改 ==========
    # .darkos-defconfig 记录上次加载的生成模板，供后续比较。
    if [ ! -f "$BUILD_DIR/.config" ] || ! cmp -s "$generated" "$BUILD_DIR/.darkos-defconfig"; then
        if [ -f "$BUILD_DIR/.config" ] && [ -f "$BUILD_DIR/.darkos-defconfig" ]; then
            local previous current
            previous=$(sed -n '/^BR2_TOOLCHAIN_/p' "$BUILD_DIR/.darkos-defconfig")
            current=$(sed -n '/^BR2_TOOLCHAIN_/p' "$generated")
            if [ "$previous" != "$current" ] && compgen -G "$BUILD_DIR/host/bin/*gcc" >/dev/null; then
                # 已导入工具链后变更配置需要清理，避免混用旧 staging/target。
                bsp_die "工具链配置已变化，请先执行 build.sh $VENDOR $SOC $BOARD clean rootfs"
            fi
        fi
        make "${ARGS[@]}" BR2_DEFCONFIG="$generated" defconfig
        cp "$generated" "$BUILD_DIR/.darkos-defconfig"
    fi
}
configure_rootfs 2>&1 | tee "$LOGS_DIR/rootfs-config.log"
# configure 到此结束；menuconfig 进入交互菜单后结束，不编译镜像。
if [ "$ACTION" = configure ]; then exit; fi
if [ "$ACTION" = menuconfig ]; then
    make "${ARGS[@]}" menuconfig
    exit
fi
# ========== 6. 构建 rootfs 并记录日志 ==========
# Buildroot 在 rootfs/build 解包和编译，向 staging/target 安装并生成镜像。
make "${ARGS[@]}" -j"$JOBS" 2>&1 | tee "$LOGS_DIR/rootfs.log"
# ========== 7. 将生成的 rootfs.* 汇总到目标 images 目录 ==========
# nullglob 让无匹配文件时得到空数组，从而明确报告未生成镜像。
shopt -s nullglob
images=("$BUILD_DIR/images/"rootfs.*)
[ "${#images[@]}" -gt 0 ] || bsp_die "Buildroot 没有生成 rootfs 镜像"
for image in "${images[@]}"; do bsp_copy_image "$image"; done
