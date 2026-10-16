#!/bin/bash
# 用法: build-rootfs.sh <vendor> <soc> <board> [build|clean|configure|menuconfig]
#                                      [--full|--incremental] [--dry-run]
# 直接使用 sources/buildroot，通过 O= 将构建过程与产物写入目标/rootfs。
set -eo pipefail

# ========== 1. 加载配置，处理当前 rootfs 组件的清理 ==========
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "$SCRIPT_DIR/../lib/bsp.sh"
bsp_load "${1:-}" "${2:-}" "${3:-}"
bsp_action "${@:4}"
BUILD_DIR="$OUTPUT_DIR/rootfs"
bsp_source rootfs
SRC_BUILDROOT="$SOURCE_DIR"
if [ "$ACTION" = clean ]; then
    if [ "$DRY_RUN" = y ]; then echo "清理 rootfs: $BUILD_DIR"; exit; fi
    # 删除当前 rootfs 构建目录和汇总镜像，保留共享下载缓存及其他组件。
    rm -rf "$BUILD_DIR"
    rm -f "$IMAGES_DIR/"rootfs.* "$IMAGES_DIR/boot.scr"
    exit
fi
echo "Buildroot: $TARGET / ${BSP_BUILDROOT_DEFCONFIG:-未指定} / jobs=$JOBS"
# ========== 2. 检查自动配置模式的工具链，处理 dry-run ==========
# 自动模式用于 QEMU 外部 glibc 工具链；其他平台可使用自身 defconfig。
if [ "${BSP_ROOTFS_EXTERNAL_AUTO:-n}" = y ]; then bsp_toolchain rootfs "${BSP_ROOTFS_MIN_GCC:-4.8.0}"; fi
export GIT_OPTIONAL_LOCKS=0
BASE_DEFCONFIG=${BSP_BUILDROOT_DEFCONFIG_FILE:-$BOARD_DIR/configs/${BSP_BUILDROOT_DEFCONFIG:-${TARGET}_defconfig}}
[[ "$BASE_DEFCONFIG" = /* ]] || BASE_DEFCONFIG="$BSP_ROOT/$BASE_DEFCONFIG"
[ -f "$BASE_DEFCONFIG" ] || bsp_die "找不到 Buildroot defconfig $BASE_DEFCONFIG"
GENERATED_DEFCONFIG="$OUTPUT_DIR/rootfs.defconfig"
STATE_ARGS=(--value arch "$ARCH" --value defconfig-name "${BSP_BUILDROOT_DEFCONFIG:-${TARGET}_defconfig}"
    --input defconfig "$BASE_DEFCONFIG" --input build-script "$SCRIPT_DIR/rootfs.sh"
    --value external-auto "${BSP_ROOTFS_EXTERNAL_AUTO:-n}" --effective-config "$BUILD_DIR/.config")
for host_tool in HOSTCC HOSTCXX; do
    if [ "$host_tool" = HOSTCC ]; then host_compiler=${HOSTCC:-gcc}; else host_compiler=${HOSTCXX:-g++}; fi
    STATE_ARGS+=(--value "$host_tool" "$host_compiler")
    # 含参数的 HOSTCC 交由 Buildroot 处理；此处只跟踪第一个可执行程序。
    host_executable=$(command -v "${host_compiler%% *}" 2>/dev/null || true)
    [ -z "$host_executable" ] || STATE_ARGS+=(--input "$host_tool-binary" "$host_executable")
done

# 外部工具链的版本、程序、headers 和主要运行库变化都不能复用旧 staging。
rootfs_track_toolchain() {
    local prefix=$1 gcc_path libc_path sysroot library compiler_path
    gcc_path=$(command -v "${prefix}gcc" 2>/dev/null || true)
    STATE_ARGS+=(--value toolchain-prefix "$prefix" --input toolchain-gcc "${gcc_path:-${prefix}gcc}")
    [ -n "$gcc_path" ] || return 0
    STATE_ARGS+=(--value toolchain-version "$("${prefix}gcc" -dumpfullversion -dumpversion 2>/dev/null || true)")
    for library in libc.a libstdc++.a libgfortran.a libgdruntime.a libgomp.a; do
        libc_path=$("${prefix}gcc" "-print-file-name=$library" 2>/dev/null || true)
        [ -f "$libc_path" ] || continue
        STATE_ARGS+=(--input "toolchain-library-$library" "$libc_path")
        if [ "$library" = libc.a ]; then
            libc_path=$(readlink -f "$libc_path")
            sysroot=$(printf '%s\n' "$libc_path" | sed -E 's:/(usr/)?lib(32|64)?([^/]*)?/([^/]*/)?libc\.a$:/:')
            [ "$sysroot" = "$libc_path" ] || STATE_ARGS+=(--tree toolchain-headers "$sysroot/usr/include")
        fi
    done
    for library in g++ gfortran gdc; do
        compiler_path=$(command -v "${prefix}$library" 2>/dev/null || true)
        STATE_ARGS+=(--input "toolchain-$library" "${compiler_path:-${prefix}$library}")
    done
}
if [ "${BSP_ROOTFS_EXTERNAL_AUTO:-n}" = y ]; then
    rootfs_track_toolchain "$CROSS_PREFIX"
else
    # 显式 Buildroot 外部工具链也跟踪可定位的编译器；内建工具链由配置和源码指纹覆盖。
    toolchain_config="$BASE_DEFCONFIG"
    if [ -f "$BUILD_DIR/.config" ] && cmp -s "$BASE_DEFCONFIG" "$BUILD_DIR/.darkos-base-defconfig"; then
        toolchain_config="$BUILD_DIR/.config"
    fi
    if grep -q '^BR2_TOOLCHAIN_EXTERNAL_PREINSTALLED=y$' "$toolchain_config"; then
        toolchain_path=$(sed -n 's/^BR2_TOOLCHAIN_EXTERNAL_PATH="\(.*\)"$/\1/p' "$toolchain_config")
        toolchain_prefix=$(sed -n 's/^BR2_TOOLCHAIN_EXTERNAL_CUSTOM_PREFIX="\(.*\)"$/\1/p' "$toolchain_config")
        if [ -n "$toolchain_path" ]; then
            [[ "$toolchain_path" = /* ]] || toolchain_path="$BSP_ROOT/$toolchain_path"
            rootfs_track_toolchain "$toolchain_path/bin/${toolchain_prefix:-aarch64-linux-gnu}-"
        fi
    fi
fi
# 配方和本地包源码变化必须重新安装；overlay 只添加/修改可以直接重新生成镜像。
for i in "${!LAYERS[@]}"; do
    layer=${LAYERS[$i]}
    for entry in Config.in configs/Config.in packages/Config.in package/Config.in; do
        STATE_ARGS+=(--input "layer-$i-$entry" "$layer/$entry")
    done
    STATE_ARGS+=(--tree "layer-$i-packages" "$layer/packages" --tree "layer-$i-package" "$layer/package"
        --overlay-tree "layer-$i-overlay" "$layer/rootfs-overlay")
done

# 可选 OP-TEE 客户端使用 sources 中固定的源码；服务安装由原生包的 external hook 完成。
OPTEE_ENABLED=${BSP_OPTEE_CLIENT_ENABLE:-n}
case "$OPTEE_ENABLED" in y|n) ;; *) bsp_die "BSP_OPTEE_CLIENT_ENABLE 必须为 y 或 n" ;; esac
STATE_ARGS+=(--value optee-client-enabled "$OPTEE_ENABLED")
if [ "$OPTEE_ENABLED" = y ]; then
    OPTEE_SOURCE=${OPTEE_CLIENT_SOURCE_DIR:-${BSP_OPTEE_CLIENT_SOURCE_DIR:-$BSP_ROOT/sources/optee_client}}
    [[ "$OPTEE_SOURCE" = /* ]] || OPTEE_SOURCE="$BSP_ROOT/$OPTEE_SOURCE"
    OPTEE_SOURCE=$(realpath -m "$OPTEE_SOURCE")
    STATE_ARGS+=(--value optee-client-source "$OPTEE_SOURCE" --value optee-client-revision "$(bsp_source_revision "$OPTEE_SOURCE")"
        --tree optee-client-files "$OPTEE_SOURCE")
fi
# menuconfig 可以添加层目录之外的 overlay；也跟踪其文件，防止删除后 target 留残余。
rootfs_plan() {
    local config="$BASE_DEFCONFIG" value path resolved i managed key is_managed index=0
    local overlay_paths=() custom_paths=() custom_args=() keys=(generic vendor soc board)
    if [ -f "$BUILD_DIR/.config" ] && cmp -s "$BASE_DEFCONFIG" "$BUILD_DIR/.darkos-base-defconfig"; then
        config="$BUILD_DIR/.config"
    fi
    value=$(sed -n 's/^BR2_ROOTFS_OVERLAY="\(.*\)"$/\1/p' "$config" | tail -n 1)
    read -r -a overlay_paths <<< "$value"
    for path in "${overlay_paths[@]}"; do
        path=${path//\$\(BR2_EXTERNAL_DARKOS_PATH\)/$BR2_EXT}
        path=${path//\$\{BR2_EXTERNAL_DARKOS_PATH\}/$BR2_EXT}
        [[ "$path" = /* ]] || path="$SRC_BUILDROOT/$path"
        resolved=$(realpath -m "$path")
        is_managed=n
        for i in "${!LAYERS[@]}"; do
            key=${keys[$i]}; managed="$BR2_EXT/layers/$key/rootfs-overlay"
            if [ "$path" = "$managed" ] || [ "$resolved" = "$(realpath -m "${LAYERS[$i]}/rootfs-overlay")" ]; then
                is_managed=y; break
            fi
        done
        [ "$is_managed" = n ] || continue
        custom_args+=(--overlay-tree "custom-overlay-$index" "$resolved")
        custom_paths+=("$resolved")
        index=$((index + 1))
    done
    custom_args+=(--value custom-overlay-paths "${custom_paths[*]}")
    bsp_build_plan rootfs "$SRC_BUILDROOT" "$BUILD_DIR" "${STATE_ARGS[@]}" "${custom_args[@]}"
}
rootfs_plan
if [ "$DRY_RUN" = y ]; then
    echo "链接各 BSP 层到 ${BR2_EXT#"$BSP_ROOT"/}；rootfs 操作: $ACTION"
    [ "$OPTEE_ENABLED" != y ] || echo "OP-TEE client: $OPTEE_SOURCE（启动服务要求 /dev/teepriv0）"
    exit
fi
[ -f "$SRC_BUILDROOT/Makefile" ] || bsp_die "找不到 Buildroot 源码 $SRC_BUILDROOT"
if [ "$OPTEE_ENABLED" = y ]; then
    [ -f "$OPTEE_SOURCE/Makefile" ] && [ -d "$OPTEE_SOURCE/tee-supplicant" ] ||
        bsp_die "缺少 OP-TEE client 源码 $OPTEE_SOURCE；请初始化 sources/optee_client 子模块"
fi

# ========== 3. 准备分层链接和 Buildroot 构建参数 ==========
mkdir -p "$BUILD_DIR" "$IMAGES_DIR" "$LOGS_DIR" "$BSP_ROOT/output/downloads"
bsp_prepare_external
ARGS=(-C "$SRC_BUILDROOT" O="$BUILD_DIR" BR2_EXTERNAL="$BR2_EXT"
    DARKOS_BSP_TARGET="$TARGET" BR2_DL_DIR="${BR2_DL_DIR:-$BSP_ROOT/output/downloads}")
[ "$OPTEE_ENABLED" != y ] || ARGS+=(OPTEE_CLIENT_OVERRIDE_SRCDIR="$OPTEE_SOURCE")
generate_rootfs_defconfig() {
    # ========== 4. 从板级模板生成本机可用的 rootfs.defconfig ==========
    # 生成文件位于 output，板级模板保留在 boards 中维护。
    local generated="$GENERATED_DEFCONFIG" gcc_path toolchain_path prefix major code headers capabilities libc_path sysroot
    cp "$BASE_DEFCONFIG" "$generated"
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
        sed -i '/^BR2_ROOTFS_OVERLAY=/d' "$generated"
        printf 'BR2_ROOTFS_OVERLAY="%s"\n' "${ROOTFS_OVERLAYS[*]}" >> "$generated"
    fi
    if [ "$OPTEE_ENABLED" = y ]; then
        sed -i '/^BR2_PACKAGE_OPTEE_CLIENT=/d; /^# BR2_PACKAGE_OPTEE_CLIENT is not set$/d; /^BR2_PACKAGE_OPTEE_CLIENT_RPMB_EMU=/d; /^# BR2_PACKAGE_OPTEE_CLIENT_RPMB_EMU is not set$/d' "$generated"
        printf 'BR2_PACKAGE_OPTEE_CLIENT=y\n# BR2_PACKAGE_OPTEE_CLIENT_RPMB_EMU is not set\n' >> "$generated"
    fi
}

# overlay 列表由层目录维护，更新列表时仍保留用户的其他 menuconfig 选项。
rootfs_template_compatible() {
    [ -f "$BUILD_DIR/.darkos-defconfig" ] && cmp -s \
        <(sed '/^BR2_ROOTFS_OVERLAY=/d' "$GENERATED_DEFCONFIG") \
        <(sed '/^BR2_ROOTFS_OVERLAY=/d' "$BUILD_DIR/.darkos-defconfig")
}
reset_rootfs() {
    local saved_config= saved_template=
    if [ -f "$BUILD_DIR/.config" ] && rootfs_template_compatible; then
        saved_config=$(cat "$BUILD_DIR/.config")
        saved_template=$(cat "$BUILD_DIR/.darkos-defconfig")
    fi
    rm -rf "$BUILD_DIR"
    rm -f "$IMAGES_DIR/"rootfs.* "$IMAGES_DIR/boot.scr"
    mkdir -p "$BUILD_DIR"
    if [ -n "$saved_config" ]; then
        printf '%s\n' "$saved_config" > "$BUILD_DIR/.config"
        printf '%s\n' "$saved_template" > "$BUILD_DIR/.darkos-defconfig"
    fi
}
configure_rootfs() {
    local generated="$GENERATED_DEFCONFIG" overlay
    # ========== 5. 按需加载配置，保留未改模板时的 menuconfig 修改 ==========
    # .darkos-defconfig 记录上次加载的生成模板，供后续比较。
    if [ ! -f "$BUILD_DIR/.config" ] || ! cmp -s "$generated" "$BUILD_DIR/.darkos-defconfig"; then
        if [ -f "$BUILD_DIR/.config" ] && rootfs_template_compatible; then
            sed -i '/^BR2_ROOTFS_OVERLAY=/d' "$BUILD_DIR/.config"
            overlay=$(sed -n '/^BR2_ROOTFS_OVERLAY=/p' "$generated")
            [ -z "$overlay" ] || printf '%s\n' "$overlay" >> "$BUILD_DIR/.config"
            make "${ARGS[@]}" olddefconfig
        else
            make "${ARGS[@]}" BR2_DEFCONFIG="$generated" defconfig
        fi
        cp "$generated" "$BUILD_DIR/.darkos-defconfig"
    else
        make "${ARGS[@]}" olddefconfig
    fi
    cp "$BASE_DEFCONFIG" "$BUILD_DIR/.darkos-base-defconfig"
    printf '%s\n%s\n' "$SRC_BUILDROOT" "$(bsp_source_revision "$SRC_BUILDROOT")" > "$BUILD_DIR/.darkos-source"
}
generate_rootfs_defconfig 2>&1 | tee "$LOGS_DIR/rootfs-config.log"
INITIAL_MODE=$BUILD_MODE
[ "$BUILD_MODE" != full ] || reset_rootfs
configure_rootfs 2>&1 | tee "$LOGS_DIR/rootfs-config.log"
# configure 到此结束；menuconfig 进入交互菜单后结束，不编译镜像。
if [ "$ACTION" = configure ]; then exit; fi
if [ "$ACTION" = menuconfig ]; then
    make "${ARGS[@]}" menuconfig
    exit
fi
# olddefconfig 可能规范化配置、改变实际 overlay；编译前刷新最终成功快照。
rootfs_plan >/dev/null
if [ "$INITIAL_MODE" = incremental ] && [ "$BUILD_MODE" = full ]; then
    rootfs_plan
    reset_rootfs
    configure_rootfs 2>&1 | tee -a "$LOGS_DIR/rootfs-config.log"
    rootfs_plan >/dev/null
fi
bsp_build_begin
# ========== 6. 构建 rootfs 并记录日志 ==========
# Buildroot 在 rootfs/build 解包和编译，向 staging/target 安装并生成镜像。
make "${ARGS[@]}" -j"$JOBS" 2>&1 | tee "$LOGS_DIR/rootfs.log"
# ========== 7. 将生成的 rootfs.* 汇总到目标 images 目录 ==========
# nullglob 让无匹配文件时得到空数组，从而明确报告未生成镜像。
shopt -s nullglob
images=("$BUILD_DIR/images/"rootfs.*)
[ "${#images[@]}" -gt 0 ] || bsp_die "Buildroot 没有生成 rootfs 镜像"
for image in "${images[@]}"; do bsp_copy_image "$image"; done
bsp_build_commit
