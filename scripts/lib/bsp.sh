#!/bin/bash
# BSP 公共函数库，由各 Bash 构建脚本 source 加载，不单独执行构建。
# 负责配置读取、工具链选择、分层文件收集、源码副本和 br2-external。

# 统一错误出口：输出到 stderr，并使当前组件返回失败。
bsp_die() { echo "错误: $*" >&2; exit 1; }

# 读取目标配置，设置当前组件使用的公共变量和四层 BSP 路径。
bsp_load() {
    # 1. 检查三个目标名，只接受普通标识符，避免把路径片段当作目标。
    VENDOR=${1:-}; SOC=${2:-}; BOARD=${3:-}
    local part config name value
    for part in "$VENDOR" "$SOC" "$BOARD"; do
        [[ "$part" =~ ^[a-zA-Z0-9_-]+$ ]] || bsp_die "需要合法的 vendor soc board 参数"
    done
    # 2. 由函数库位置定位工程，找到 boards/<vendor>/<soc>/<board>/bsp.mk。
    BSP_ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
    BOARD_DIR="$BSP_ROOT/boards/$VENDOR/$SOC/$BOARD"
    [ -f "$BOARD_DIR/bsp.mk" ] || bsp_die "找不到板级配置 $BOARD_DIR/bsp.mk"
    # 3. bsp.mk 是 Makefile 语法；用 Make 展开 include、:= 和路径变量。
    # 只输出 BSP_* 变量，随后逐项赋给 Bash，避免用 eval 执行配置文本。
    config=$(make --no-print-directory -s -f - BSP_ROOT="$BSP_ROOT" \
        BOARD_DIR="$BOARD_DIR" print-bsp-config <<'MAKE'
include $(BOARD_DIR)/bsp.mk
.PHONY: print-bsp-config
print-bsp-config:
	$(foreach var,$(sort $(filter BSP_%,$(.VARIABLES))),$(info $(var)=$($(var))))
	@:
MAKE
    ) || bsp_die "无法读取 bsp.mk"
    while IFS='=' read -r name value; do
        [[ "$name" =~ ^BSP_[A-Z0-9_]+$ ]] || continue
        # 运行时目录以入口选定的目标为准，忽略配置中用于描述的同名路径。
        case "$name" in BSP_ROOT|BSP_OUTPUT_DIR|BSP_IMAGES_DIR|BSP_OUTPUT_NAME) continue ;; esac
        printf -v "$name" '%s' "$value"
    done <<< "$config"
    # 4. 统一组件、镜像、日志及 external 目录；环境 JOBS 可覆盖板级默认值。
    TARGET="${VENDOR}_${SOC}_${BOARD}"
    OUTPUT_DIR="$BSP_ROOT/output/$TARGET"
    IMAGES_DIR="$OUTPUT_DIR/images"
    LOGS_DIR="$OUTPUT_DIR/logs"
    BR2_EXT="$OUTPUT_DIR/br2-external"
    ARCH=${BSP_ARCH:-arm64}
    JOBS=${JOBS:-${BSP_JOBS:-$(nproc)}}
    [[ "$JOBS" =~ ^[1-9][0-9]*$ ]] || bsp_die "JOBS 必须为正整数"
    # 5. 后续补丁、包配置和 overlay 都按通用到板级的顺序读取。
    LAYERS=("$BSP_ROOT/common" "$BSP_ROOT/vendors/$VENDOR/common"
        "$BSP_ROOT/vendors/$VENDOR/$SOC" "$BOARD_DIR")
}

# 校验普通组件支持的操作，防止未知动作被当成构建或清理执行。
bsp_action() {
    ACTION=${1:-build}
    case "$ACTION" in build|clean|--dry-run) ;; *) bsp_die "不支持的操作 $ACTION" ;; esac
}

# 按组件选择交叉编译器并检查最低版本；结果写入 CROSS_PREFIX/CROSS_VERSION。
bsp_toolchain() {
    local stage=$1 min_version=$2 requested version candidate override
    # 1. 优先使用组件环境变量，其次组件板级变量、通用环境变量及通用板级值。
    case "$stage" in
        kernel) requested=${KERNEL_CROSS_COMPILE:-${BSP_KERNEL_CROSS_COMPILE:-${CROSS_COMPILE:-${BSP_CROSS_COMPILE:-aarch64-linux-gnu-}}}} ;;
        uboot) requested=${UBOOT_CROSS_COMPILE:-${BSP_UBOOT_CROSS_COMPILE:-${CROSS_COMPILE:-${BSP_CROSS_COMPILE:-aarch64-linux-gnu-}}}} ;;
        rootfs) requested=${ROOTFS_CROSS_COMPILE:-${BSP_ROOTFS_CROSS_COMPILE:-${CROSS_COMPILE:-${BSP_CROSS_COMPILE:-aarch64-linux-gnu-}}}} ;;
    esac
    # 2. 记录显式覆盖；用户明确选择时不自动换成另一套工具链。
    case "$stage" in
        kernel) override=${KERNEL_CROSS_COMPILE:-}${BSP_KERNEL_CROSS_COMPILE:-} ;;
        uboot) override=${UBOOT_CROSS_COMPILE:-}${BSP_UBOOT_CROSS_COMPILE:-} ;;
        rootfs) override=${ROOTFS_CROSS_COMPILE:-}${BSP_ROOTFS_CROSS_COMPILE:-} ;;
    esac
    CROSS_PREFIX=$requested
    # 3. 仅开启 BSP_TOOLCHAIN_AUTO 且没有显式覆盖时扫描已安装的工具链。
    # 按候选顺序选择第一个满足最低版本的编译器，不一定选择最新版本。
    if [ "${BSP_TOOLCHAIN_AUTO:-n}" = y ] && [ -z "${CROSS_COMPILE:-}$override" ]; then
        local candidates=("$requested" /usr/bin/aarch64-linux-gnu-)
        # 无匹配目录时跳过 glob，避免把带星号的文本当成编译器路径。
        shopt -s nullglob
        local compiler
        for compiler in /opt/*/bin/aarch64*-gcc /opt/vs-linux/x86-arm/*/bin/aarch64*-gcc; do
            candidates+=("${compiler%gcc}")
        done
        shopt -u nullglob
        for candidate in "${candidates[@]}"; do
            version=$("${candidate}gcc" -dumpfullversion -dumpversion 2>/dev/null) || continue
            if [ "$(printf '%s\n' "$min_version" "$version" | sort -V | head -n 1)" = "$min_version" ]; then
                CROSS_PREFIX=$candidate
                break
            fi
        done
    fi
    # 4. 对最终选择再次检查；显式指定旧版本或无效路径时明确报错。
    version=$("${CROSS_PREFIX}gcc" -dumpfullversion -dumpversion 2>/dev/null) || bsp_die "找不到 ${CROSS_PREFIX}gcc；可设置 ${stage^^}_CROSS_COMPILE"
    [ "$(printf '%s\n' "$min_version" "$version" | sort -V | head -n 1)" = "$min_version" ] || bsp_die "$stage 使用 GCC $version，要求至少 $min_version；请设置 ${stage^^}_CROSS_COMPILE"
    CROSS_VERSION=$version
    echo "工具链 ($stage): ${CROSS_PREFIX}gcc ($version)"
}

# 收集组件补丁和实际存在的配置片段，输出 PATCH_FILES/CONFIG_FRAGMENTS 数组。
bsp_collect() {
    local component=$1 layer f fragment
    PATCH_FILES=(); CONFIG_FRAGMENTS=()
    for layer in "${LAYERS[@]}"; do
        # 1. 按四层顺序遍历；同层 *.patch 按 shell 文件名顺序收集。
        [ -d "$layer" ] || continue
        shopt -s nullglob
        for f in "$layer/patches/$component/"*.patch; do PATCH_FILES+=("$f"); done
        shopt -u nullglob
        # 2. Linux 片段按层命名；U-Boot 各层统一使用 uboot.fragment。
        case "$component" in
            linux)
                case "$layer" in
                    "${LAYERS[0]}") fragment=common.fragment ;;
                    "${LAYERS[1]}") fragment="$VENDOR.fragment" ;;
                    "${LAYERS[2]}") fragment="$SOC.fragment" ;;
                    *) fragment=kernel.fragment ;;
                esac ;;
            uboot) fragment=uboot.fragment ;;
        esac
        [ ! -f "$layer/configs/$fragment" ] || CONFIG_FRAGMENTS+=("$layer/configs/$fragment")
    done
}

# 为一个目标准备源码副本：首次 rsync，已有 Makefile 时复用以保留增量构建。
bsp_copy_source() {
    local src=$1 dest=$2
    [ -d "$src" ] || bsp_die "找不到源码 $src"
    if [ -f "$dest/Makefile" ]; then
        echo "复用构建目录: ${dest#"$BSP_ROOT"/}（更新源码或补丁后请 clean）"
        return
    fi
    mkdir -p "$dest"
    # 不复制 Git 数据、原目录 .config 及常见编译中间文件。
    # 后续补丁和板级文件只写入这个副本。
    rsync -a --exclude=.git --exclude=.config --exclude='*.o' --exclude='*.a' \
        --exclude='*.ko' --exclude='*.mod' --exclude='*.cmd' --exclude='*.tmp' \
        --exclude=modules.order --exclude=Module.symvers "$src/" "$dest/"
}

# 对副本应用补丁：正向试运行成功才应用；反向成功表示已应用，可以跳过。
# 两个方向都失败时停止构建，避免使用缺少补丁的源码继续编译。
bsp_apply_patches() {
    local dest=$1 p
    for p in "${PATCH_FILES[@]}"; do
        if patch -d "$dest" -p1 --forward --batch --dry-run < "$p" >/dev/null 2>&1; then
            patch -d "$dest" -p1 --forward --batch < "$p"
        elif patch -d "$dest" -p1 --reverse --batch --dry-run < "$p" >/dev/null 2>&1; then
            echo "已应用: ${p#"$BSP_ROOT"/}"
        else bsp_die "补丁失败: ${p#"$BSP_ROOT"/}"; fi
    done
}

# 检查必要产物非空，再复制到统一 images 目录；name 可指定输出文件名。
bsp_copy_image() {
    local src=$1 name=${2:-$(basename "$1")}
    [ -s "$src" ] || bsp_die "缺少构建产物 $src"
    mkdir -p "$IMAGES_DIR"
    cp "$src" "$IMAGES_DIR/$name"
    echo "镜像: ${IMAGES_DIR#"$BSP_ROOT"/}/$name"
}

# 生成每个目标独立的 br2-external；链接指向 BSP 层中的原配置和软件包。
bsp_prepare_external() {
    local i layer key entry path
    local keys=(common vendor soc board)
    # 1. 创建 external 的三个必需入口文件，名称 DARKOS 对应变量
    # BR2_EXTERNAL_DARKOS_PATH，供 Kconfig、Make 和包配方引用。
    mkdir -p "$BR2_EXT/layers" "$BR2_EXT/configs"
    printf 'name: DARKOS\ndesc: DarkOS %s\n' "$TARGET" > "$BR2_EXT/external.desc"
    printf '# Generated by DarkOS; edit the linked BSP files.\n' > "$BR2_EXT/Config.in"
    printf '# Generated by DarkOS; common -> vendor -> SoC -> board.\n' > "$BR2_EXT/external.mk"
    ROOTFS_OVERLAYS=()
    # 2. 刷新各层相对符号链接；不存在的可选层不生成链接。
    for i in "${!LAYERS[@]}"; do
        layer=${LAYERS[$i]}; key=${keys[$i]}
        rm -f "$BR2_EXT/layers/$key"
        [ -d "$layer" ] || continue
        ln -s "$(realpath --relative-to="$BR2_EXT/layers" "$layer")" "$BR2_EXT/layers/$key"
        # 3. 只 source 已存在的 Kconfig 入口，避免空目录造成配置加载失败。
        for entry in Config.in configs/Config.in packages/Config.in package/Config.in; do
            [ ! -f "$layer/$entry" ] || printf 'source "$BR2_EXTERNAL_DARKOS_PATH/layers/%s/%s"\n' "$key" "$entry" >> "$BR2_EXT/Config.in"
        done
        # 4. 自动 include 包配方，支持 packages/ 和 package/ 两种目录名。
        # 包名应保持唯一；这套层级不提供同名 Buildroot 包的自动覆盖。
        for entry in packages package; do
            printf 'include $(sort $(wildcard $(BR2_EXTERNAL_DARKOS_PATH)/layers/%s/%s/*.mk $(BR2_EXTERNAL_DARKOS_PATH)/layers/%s/%s/*/*.mk))\n' "$key" "$entry" "$key" "$entry" >> "$BR2_EXT/external.mk"
        done
        # 5. 记录 overlay 路径，交给 Buildroot 按相同层级顺序安装文件。
        for entry in rootfs-overlay; do
            [ ! -d "$layer/$entry" ] || ROOTFS_OVERLAYS+=("$BR2_EXT/layers/$key/$entry")
        done
    done
    # 6. 检查并链接板级 defconfig，让它出现在 external 的 configs 目录中。
    local defconfig=${BSP_BUILDROOT_DEFCONFIG_FILE:-$BOARD_DIR/configs/${BSP_BUILDROOT_DEFCONFIG:-${TARGET}_defconfig}}
    [ -f "$defconfig" ] || bsp_die "找不到 Buildroot defconfig $defconfig"
    ln -sfn "$(realpath --relative-to="$BR2_EXT/configs" "$defconfig")" "$BR2_EXT/configs/${BSP_BUILDROOT_DEFCONFIG:-${TARGET}_defconfig}"
    echo "br2-external: ${BR2_EXT#"$BSP_ROOT"/}"
}
