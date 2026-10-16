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

# 源码目录可以按目标选择；相对路径始终相对于工程根目录。
bsp_source() {
    local stage=$1 requested
    case "$stage" in
        kernel) requested=${KERNEL_SOURCE_DIR:-${BSP_KERNEL_SOURCE_DIR:-sources/linux}} ;;
        uboot) requested=${UBOOT_SOURCE_DIR:-${BSP_UBOOT_SOURCE_DIR:-sources/u-boot}} ;;
        rootfs) requested=${BUILDROOT_SOURCE_DIR:-${BSP_BUILDROOT_SOURCE_DIR:-sources/buildroot}} ;;
        *) bsp_die "未知源码组件 $stage" ;;
    esac
    [[ "$requested" = /* ]] || requested="$BSP_ROOT/$requested"
    SOURCE_DIR=$(realpath -m "$requested")
}

# 只读取源码根目录自身的 Git 数据，避免把无 Git 的源码当成主仓库。
bsp_source_revision() {
    if [ -e "$1/.git" ]; then
        git -C "$1" rev-parse HEAD 2>/dev/null || printf 'unknown\n'
    else
        printf 'unversioned\n'
    fi
}

# BSP 变量按名称归入配置快照的分段；冲突时靠前的分段优先。
bsp_config_section() {
    case "$1" in
        BSP_VENDOR|BSP_SOC|BSP_BOARD|BSP_BOARD_NAME|BSP_BOARD_VERSION|BSP_ARCH|BSP_CROSS_COMPILE|BSP_TOOLCHAIN_AUTO|BSP_JOBS|BSP_ROOT)
            printf '目标与全局' ;;
        BSP_PACK_SCRIPT|BSP_IMAGE_*|BSP_BOOT_*|BSP_BOOTLOADER_*|BSP_QEMU_*|BSP_KERNEL_CMDLINE|BSP_ROOTFS_PARTUUID)
            printf '打包与分区' ;;
        BSP_UBOOT_*) printf 'U-Boot' ;;
        BSP_KERNEL_*|BSP_DEFCONFIG|BSP_DEFCONFIG_FILE|BSP_DTS_NAME|BSP_DTS_DIR) printf '内核' ;;
        BSP_BUILDROOT_*|BSP_ROOTFS_*) printf 'Buildroot rootfs' ;;
        BSP_OPTEE_*) printf 'OP-TEE' ;;
        *) printf '其他' ;;
    esac
}

# config 入口：显示继承后的值和构建实际使用的文件，并把最终变量写入快照。
bsp_print_config() {
    local name stage file layer layers=""
    echo "配置层: ${LAYERS[*]}"
    while IFS= read -r name; do
        printf '%s=%s\n' "$name" "${!name}"
    done < <(compgen -A variable BSP_ | sort)
    printf 'OUTPUT_DIR=%s\n' "$OUTPUT_DIR"
    for stage in kernel uboot rootfs; do
        bsp_source "$stage"
        printf '%s source=%s\n' "$stage" "$SOURCE_DIR"
        printf '%s commit=%s\n' "$stage" "$(bsp_source_revision "$SOURCE_DIR")"
    done
    for stage in linux uboot; do
        bsp_collect "$stage"
        for file in "${PATCH_FILES[@]}"; do printf '%s patch=%s\n' "$stage" "$file"; done
        for file in "${CONFIG_FRAGMENTS[@]}"; do printf '%s fragment=%s\n' "$stage" "$file"; done
    done
    printf 'BL31=%s\nROCKCHIP_TPL=%s\n' \
        "${BL31:-${BSP_UBOOT_BL31:-}}" "${ROCKCHIP_TPL:-${BSP_UBOOT_TPL:-}}"
    # 分区/打包布局由目标后端的 dry-run 提供，顺带提前暴露非法分区参数。
    local backend=${BSP_PACK_SCRIPT:-} layout=""
    if [ -n "$backend" ]; then
        [[ "$backend" = /* ]] || backend="$BSP_ROOT/$backend"
        [ -f "$backend" ] || bsp_die "找不到打包脚本 $backend"
        layout=$(bash "$backend" "$VENDOR" "$SOC" "$BOARD" --dry-run)
        echo "分区/打包布局:"
        printf '%s\n' "$layout"
    fi
    # 快照只记录最终变量值，供查阅与目标间对比；源码提交等易变诊断不写入。
    if [ -z "${DRY_RUN:-}" ]; then
        for layer in "${LAYERS[@]}"; do layers="${layers:+$layers }${layer#"$BSP_ROOT"/}"; done
        local section
        local sections=("目标与全局" "U-Boot" "内核" "Buildroot rootfs" "打包与分区" "OP-TEE" "其他")
        local -A grouped=()
        while IFS= read -r name; do
            section=$(bsp_config_section "$name")
            grouped[$section]+=" $name"
        done < <(compgen -A variable BSP_ | sort)
        mkdir -p "$OUTPUT_DIR"
        {
            printf '# DarkOS BSP 配置快照：config 命令生成，勿手工编辑。\n'
            printf '# 目标: %s\n' "$TARGET"
            printf '# 层级: %s\n' "$layers"
            for section in "${sections[@]}"; do
                [ -n "${grouped[$section]:-}" ] || continue
                printf '\n# %s\n' "$section"
                if [ "$section" = 目标与全局 ]; then
                    printf 'OUTPUT_DIR=%s\n' "$OUTPUT_DIR"
                fi
                for name in ${grouped[$section]}; do
                    printf '%s=%s\n' "$name" "${!name}"
                done
                # 环境覆盖后的有效固件路径跟随 U-Boot 段落。
                [ "$section" != U-Boot ] || printf 'BL31=%s\nROCKCHIP_TPL=%s\n' \
                    "${BL31:-${BSP_UBOOT_BL31:-}}" "${ROCKCHIP_TPL:-${BSP_UBOOT_TPL:-}}"
            done
            [ -z "$layout" ] || { printf '\n# 分区/打包布局:\n'; printf '%s\n' "$layout" | sed 's/^/# /'; }
        } > "$OUTPUT_DIR/bsp.config"
        echo "配置快照: ${OUTPUT_DIR#"$BSP_ROOT"/}/bsp.config"
    fi
}

# 组件操作和构建策略可以任意顺序出现；未知参数绝不隐式执行清理。
bsp_action() {
    ACTION=build; BUILD_POLICY=auto; DRY_RUN=n
    local option action_seen=n
    for option in "$@"; do
        case "$option" in
            build|clean|configure|menuconfig)
                [ "$action_seen" = n ] || bsp_die "只能指定一个组件操作"
                ACTION=$option; action_seen=y ;;
            --dry-run) DRY_RUN=y ;;
            --full|--incremental)
                [ "$BUILD_POLICY" = auto ] || bsp_die "--full 与 --incremental 只能指定一个"
                BUILD_POLICY=${option#--} ;;
            *) bsp_die "不支持的操作或选项 $option" ;;
        esac
    done
    [ "$ACTION" != clean ] || [ "$BUILD_POLICY" = auto ] || bsp_die "clean 不接受编译策略"
}

# 输入快照和状态均由 Python 处理；计划仅保存在 Bash 内存，dry-run 不写 output。
# --value/--input/--tree 为全量输入，--update-tree/--overlay-tree 支持新增/修改增量。
bsp_build_plan() {
    local description
    BUILD_PLAN_JSON=$(python3 "$BSP_ROOT/scripts/lib/build-state.py" plan "$@" \
        --policy "${BUILD_POLICY:-auto}") || return 1
    description=$(printf '%s' "$BUILD_PLAN_JSON" | python3 "$BSP_ROOT/scripts/lib/build-state.py" describe) || return 1
    BUILD_MODE=${description%%$'\n'*}
    printf '%s\n' "${description#*$'\n'}"
}

# 必须在组件清理之后、首次写构建输入之前调用；失败的构建下次自动全量。
bsp_build_begin() {
    printf '%s' "$BUILD_PLAN_JSON" | python3 "$BSP_ROOT/scripts/lib/build-state.py" begin
}

# 只有组件产物全部验证并复制成功后才记录成功输入。
bsp_build_commit() {
    printf '%s' "$BUILD_PLAN_JSON" | python3 "$BSP_ROOT/scripts/lib/build-state.py" commit
}

# 工具链同版本但二进制替换也需要重新编译，避免混用不同编译器的中间产物。
bsp_toolchain_identity() {
    local compiler digest
    compiler=$(command -v "${CROSS_PREFIX}gcc") || bsp_die "找不到 ${CROSS_PREFIX}gcc"
    compiler=$(realpath "$compiler")
    digest=$(sha256sum "$compiler")
    printf '%s|%s|%s\n' "$compiler" "$CROSS_VERSION" "${digest%% *}"
}

# 优先使用系统依赖；本机验证时下载到 output 的工具可作为隔离后备。
bsp_host_tools() {
    local sysroot="$BSP_ROOT/output/host-tools/sysroot"
    if ! command -v swig >/dev/null && [ -x "$sysroot/usr/bin/swig" ]; then
        export PATH="$sysroot/usr/bin:$PATH"
        export SWIG_LIB="${SWIG_LIB:-$sysroot/usr/share/swig4.0}"
    fi
    if ! python3 -c 'import elftools' >/dev/null 2>&1 &&
        [ -d "$sysroot/usr/lib/python3/dist-packages/elftools" ]; then
        export PYTHONPATH="$sysroot/usr/lib/python3/dist-packages${PYTHONPATH:+:$PYTHONPATH}"
    fi
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
    local component=$1 layer f fragment suffix patch_var fragment_var
    local patch_dirs=() fragments=()
    PATCH_FILES=(); CONFIG_FRAGMENTS=()
    case "$component" in
        linux) suffix=LINUX ;;
        uboot) suffix=UBOOT ;;
        *) bsp_die "未知补丁组件 $component" ;;
    esac
    patch_var="BSP_PATCH_DIRS_$suffix"
    fragment_var="BSP_FRAGMENTS_$suffix"
    # 未声明时使用四层约定；显式空列表表示禁用该项。
    if [[ -v "$patch_var" ]]; then
        read -r -a patch_dirs <<< "${!patch_var}"
    else
        for layer in "${LAYERS[@]}"; do patch_dirs+=("$layer/patches/$component"); done
    fi
    for layer in "${patch_dirs[@]}"; do
        [[ "$layer" = /* ]] || layer="$BSP_ROOT/$layer"
        [ -d "$layer" ] || continue
        shopt -s nullglob
        for f in "$layer/"*.patch; do PATCH_FILES+=("$f"); done
        shopt -u nullglob
    done
    if [[ -v "$fragment_var" ]]; then
        read -r -a fragments <<< "${!fragment_var}"
    else
    for layer in "${LAYERS[@]}"; do
        # Linux 片段按层命名；U-Boot 各层统一使用 uboot.fragment。
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
        fragments+=("$layer/configs/$fragment")
    done
    fi
    for f in "${fragments[@]}"; do
        [[ "$f" = /* ]] || f="$BSP_ROOT/$f"
        if [[ -v "$fragment_var" ]]; then
            [ -f "$f" ] || bsp_die "缺少显式配置片段 $f"
        fi
        [ ! -f "$f" ] || CONFIG_FRAGMENTS+=("$f")
    done
}

# 按输入计划同步改动的源码；未改动文件保留 BSP 补丁和构建产物。
bsp_copy_source() {
    local src=$1 dest=$2
    [ -n "${BUILD_PLAN_JSON:-}" ] || bsp_die "复制源码前必须先调用 bsp_build_plan"
    [ "$(realpath -m "$src")" = "$SOURCE_DIR" ] || bsp_die "源码计划与同步目录不一致"
    [ "$(realpath -m "$dest")" = "$BUILD_DIR" ] || bsp_die "构建计划与同步目录不一致"
    printf '%s' "$BUILD_PLAN_JSON" | python3 "$BSP_ROOT/scripts/lib/build-state.py" copy-source
}

# Buildroot 使用共享源码和 O=；版本变化同样需要清理旧 package stamp。
bsp_check_rootfs_source() {
    local src=$1 dest=$2 stamp
    [ -f "$src/Makefile" ] || bsp_die "找不到 Buildroot 源码 $src"
    stamp=$(printf '%s\n%s\n' "$(realpath "$src")" "$(bsp_source_revision "$src")")
    if [ -f "$dest/.config" ]; then
        [ -f "$dest/.darkos-source" ] || bsp_die "旧 rootfs 输出没有源码记录，请先 clean rootfs"
        [ "$(cat "$dest/.darkos-source")" = "$stamp" ] || bsp_die "Buildroot 源码路径或提交已变化，请先 clean rootfs"
    fi
    mkdir -p "$dest"
    printf '%s\n' "$stamp" > "$dest/.darkos-source"
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
