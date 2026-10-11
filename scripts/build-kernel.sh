#!/bin/bash
# 用法: ./scripts/build-kernel.sh <vendor> <soc> <board> [clean|--dry-run]
# 示例: ./scripts/build-kernel.sh rockchip rk3588s evb1
#       ./scripts/build-kernel.sh rockchip rk3588s evb1 clean
#       ./scripts/build-kernel.sh rockchip rk3588s evb1 --dry-run

# 构建沿用源码副本方案；pipefail 保证 make 失败时不会被 tee 掩盖。
set -eo pipefail

# ========== 准备阶段: 读取配置、处理组件清理、检查工具链 ==========
source "$(dirname "$0")/lib/bsp.sh"
bsp_load "${1:-}" "${2:-}" "${3:-}"
bsp_action "${4:-build}"
SRC_KERNEL="$BSP_ROOT/sources/linux"
BUILD_DIR="$OUTPUT_DIR/kernel"
LOG_FILE="$LOGS_DIR/kernel.log"

if [ "$ACTION" = "clean" ]; then
    # 仅清理当前目标的内核组件，保留 U-Boot、rootfs 和共享下载缓存。
    echo "清理内核: ${BUILD_DIR#"$BSP_ROOT"/}"
    rm -rf "$BUILD_DIR"
    rm -f "$IMAGES_DIR/"Image* "$IMAGES_DIR/zImage" "$IMAGES_DIR/"*.dtb "$IMAGES_DIR/boot.scr"
    exit 0
fi
[ -d "$SRC_KERNEL" ] || bsp_die "找不到内核源码 $SRC_KERNEL"
DEFCONFIG=${BSP_DEFCONFIG:-defconfig}
MIN_GCC=$(ARCH="$ARCH" "$SRC_KERNEL/scripts/min-tool-version.sh" gcc)
# 最低版本由当前内核源码决定，再由公共函数选择或校验工具链。
bsp_toolchain kernel "$MIN_GCC"
CROSS_COMPILE=$CROSS_PREFIX

# ==================== 信息面板 ====================
KERNEL_VERSION="$(git -C "$SRC_KERNEL" describe --tags --always 2>/dev/null || echo 'unknown')"
KERNEL_BRANCH="$(git -C "$SRC_KERNEL" rev-parse --abbrev-ref HEAD 2>/dev/null || echo 'unknown')"
CROSS_GCC_VER="$("${CROSS_COMPILE}gcc" --version 2>/dev/null || true)"
CROSS_GCC_VER=${CROSS_GCC_VER%%$'\n'*}
CROSS_GCC_VER=${CROSS_GCC_VER:-未找到工具链}

PATCH_LIST=()
# 枚举四层补丁供面板展示和后续应用，同层按文件名排序。
PATCH_DIRS=(
    "$BSP_ROOT/common/patches/linux"
    "$BSP_ROOT/vendors/$VENDOR/common/patches/linux"
    "$BSP_ROOT/vendors/$VENDOR/$SOC/patches/linux"
    "$BOARD_DIR/patches/linux"
)
for dir in "${PATCH_DIRS[@]}"; do
    [ -d "$dir" ] || continue
    for p in $(ls "$dir"/*.patch 2>/dev/null | sort); do
        PATCH_LIST+=("$(realpath --relative-to="$BSP_ROOT" "$p")")
    done
done

FRAGMENT_LIST=()
# 片段展示用相对路径，实际合并使用绝对路径；不存在的片段不参与合并。
FRAGMENT_FILES=()
FRAGMENT_CANDIDATES=(
    "$BSP_ROOT/common/configs/common.fragment"
    "$BSP_ROOT/vendors/$VENDOR/common/configs/${VENDOR}.fragment"
    "$BSP_ROOT/vendors/$VENDOR/$SOC/configs/${SOC}.fragment"
    "$BOARD_DIR/configs/kernel.fragment"
)
for f in "${FRAGMENT_CANDIDATES[@]}"; do
    if [ -f "$f" ]; then
        FRAGMENT_LIST+=("$(realpath --relative-to="$BSP_ROOT" "$f")")
        FRAGMENT_FILES+=("$f")
    fi
done

# 颜色
C_BOLD="\033[1m"
C_DIM="\033[2m"
C_CYAN="\033[36m"
C_GREEN="\033[32m"
C_YELLOW="\033[33m"
C_RESET="\033[0m"

echo ""
echo -e "${C_BOLD}${C_CYAN}DarkOS BSP · Kernel Build${C_RESET}"
echo -e "${C_DIM}────────────────────────────────────────────${C_RESET}"
echo -e "  ${C_BOLD}Target${C_RESET}"
echo -e "    vendor       ${VENDOR}"
echo -e "    soc          ${SOC}"
echo -e "    board        ${BOARD}"
echo -e "    arch         ${ARCH}"
echo ""
echo -e "  ${C_BOLD}Toolchain${C_RESET}"
echo -e "    prefix       ${CROSS_COMPILE}"
echo -e "    version      ${CROSS_GCC_VER}"
echo ""
echo -e "  ${C_BOLD}Kernel${C_RESET}"
echo -e "    version      ${KERNEL_VERSION}"
echo -e "    branch       ${KERNEL_BRANCH}"
echo -e "    defconfig    ${DEFCONFIG}"
echo -e "    jobs         ${JOBS}"
echo -e "    source       sources/linux"
echo -e "    output       output/${VENDOR}_${SOC}_${BOARD}"
echo ""

if [ ${#PATCH_LIST[@]} -gt 0 ]; then
    echo -e "  ${C_BOLD}Patches ${C_DIM}(${#PATCH_LIST[@]})${C_RESET}"
    for p in "${PATCH_LIST[@]}"; do
        echo -e "    ${C_GREEN}•${C_RESET} $p"
    done
else
    echo -e "  ${C_BOLD}Patches${C_RESET} ${C_DIM}(none)${C_RESET}"
fi
echo ""

if [ ${#FRAGMENT_LIST[@]} -gt 0 ]; then
    echo -e "  ${C_BOLD}Config Fragments ${C_DIM}(${#FRAGMENT_LIST[@]})${C_RESET}"
    for f in "${FRAGMENT_LIST[@]}"; do
        echo -e "    ${C_YELLOW}•${C_RESET} $f"
    done
else
    echo -e "  ${C_BOLD}Config Fragments${C_RESET} ${C_DIM}(none)${C_RESET}"
fi

echo ""
echo -e "${C_DIM}────────────────────────────────────────────${C_RESET}"

if [ "$ACTION" = "--dry-run" ]; then
    echo "Dry-run 模式，未执行构建。"
    exit 0
fi

# 交互调用预留取消时间；没有标准输入时继续构建。
read -t 3 -p "3 秒后开始构建，按 Ctrl+C 取消... " || true
echo ""

mkdir -p "$OUTPUT_DIR" "$IMAGES_DIR" "$LOGS_DIR"

# ========== 1. 拷贝源码 ==========
echo ""
echo ">>> [1/5] 拷贝内核源码"
if [ -d "$BUILD_DIR" ]; then
    # 复用副本与编译缓存；原始源码或补丁更新后需要先清理此组件。
    echo "    已存在，跳过拷贝（clean 后重来）"
else
    rsync -a --delete \
        --exclude='.git' --exclude='.config' \
        --exclude='*.o' --exclude='*.a' --exclude='*.ko' \
        --exclude='*.mod' --exclude='*.cmd' --exclude='*.tmp' \
        --exclude='modules.order' --exclude='Module.symvers' \
        "$SRC_KERNEL/" "$BUILD_DIR/"
    echo "    拷贝完成: $BUILD_DIR"
fi

cd "$BUILD_DIR"

# ========== 2. 应用补丁 ==========
echo ""
echo ">>> [2/5] 应用补丁"
apply_patch() {
    # 先检查正向应用；若反向可应用，说明补丁已存在于副本中。
    local p=$1
    if patch -p1 --forward --dry-run < "$p" >/dev/null 2>&1; then
        patch -p1 --forward < "$p"
        echo "    ✔ $(basename "$p")"
    elif patch -p1 --reverse --dry-run < "$p" >/dev/null 2>&1; then
        echo "    ↷ 已应用，跳过: $(basename "$p")"
    else
        echo "    ✘ 失败: $(basename "$p")"
        return 1
    fi
}
for dir in "${PATCH_DIRS[@]}"; do
    [ -d "$dir" ] || continue
    echo "  层: $dir"
    for p in $(ls "$dir"/*.patch 2>/dev/null | sort); do
        apply_patch "$p" || exit 1
    done
done

# ========== 2.5 拷贝板级 DTS ==========
if [ -d "$BOARD_DIR/dts" ]; then
    # 物理板子的 DTS 写入源码副本；QEMU 没有此目录，由模拟器提供 DTB。
    echo ""
    echo ">>> [2.5/5] 拷贝板级 DTS"
    DTS_DEST="$BUILD_DIR/arch/$ARCH/boot/dts/$VENDOR"
    mkdir -p "$DTS_DEST"
    (
        # 子 shell 仅改变复制时的工作目录，使 cp 显示相对 BSP 根目录的路径。
        # 空目录等复制错误仍按原脚本忽略，后续 make 负责检查引用的设备树。
        cd "$BSP_ROOT" || exit 1
        cp -v "${BOARD_DIR#"$BSP_ROOT"/}/dts/"* \
            "${DTS_DEST#"$BSP_ROOT"/}/" 2>/dev/null || true
    )
fi

# ========== 3. 配置合并 ==========
echo ""
echo ">>> [3/5] 配置内核"
if [ -n "${BSP_DEFCONFIG_FILE:-}" ]; then
    # 让自定义配置成为副本中的 make defconfig 目标，不修改 sources/linux。
    [ -f "$BSP_DEFCONFIG_FILE" ] || {
        echo "错误: 找不到板级内核配置 $BSP_DEFCONFIG_FILE"
        exit 1
    }
    cp -v "$BSP_DEFCONFIG_FILE" "$BUILD_DIR/arch/$ARCH/configs/$DEFCONFIG"
fi
make ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" "$DEFCONFIG"

if [ ${#FRAGMENT_LIST[@]} -gt 0 ]; then
    # -m 仅合并文本；下面的 olddefconfig 使用正确 ARCH/工具链补齐配置。
    echo "  合并配置片段..."
    "$BUILD_DIR/scripts/kconfig/merge_config.sh" \
        -m -O "$BUILD_DIR" "$BUILD_DIR/.config" "${FRAGMENT_FILES[@]}"
fi
make ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" olddefconfig

# ========== 4. 编译 ==========
echo ""
echo ">>> [4/5] 编译内核 (jobs=$JOBS)"
read -r -a BUILD_TARGETS <<< "${BSP_KERNEL_TARGETS:-}"
# 板级指定 Image 等目标时只编译所需产物；未指定时执行内核默认目标。
make ARCH="$ARCH" CROSS_COMPILE="$CROSS_COMPILE" -j"$JOBS" "${BUILD_TARGETS[@]}" 2>&1 | tee "$LOG_FILE"

# ========== 5. 输出镜像 ==========
echo ""
echo ">>> [5/5] 输出镜像"
case $ARCH in
    # 必需的内核镜像必须存在；可选压缩镜像和 DTB 按实际生成情况汇总。
    arm64)
        bsp_copy_image arch/arm64/boot/Image
        shopt -s nullglob
        for image in arch/arm64/boot/Image.*; do bsp_copy_image "$image"; done
        shopt -u nullglob
        cp -v arch/arm64/boot/dts/$VENDOR/*.dtb "$IMAGES_DIR/" 2>/dev/null || true
        ;;
    arm)
        bsp_copy_image arch/arm/boot/zImage
        cp -v arch/arm/boot/dts/*.dtb       "$IMAGES_DIR/" 2>/dev/null || true
        ;;
    riscv)
        bsp_copy_image arch/riscv/boot/Image
        ;;
esac

echo ""
echo "=== 构建完成 ==="
echo "编译目录: $BUILD_DIR"
echo "镜像输出: $IMAGES_DIR"
echo "构建日志: $LOG_FILE"
ls -lh "$IMAGES_DIR" 2>/dev/null || true
