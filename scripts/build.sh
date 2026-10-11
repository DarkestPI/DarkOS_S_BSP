#!/bin/bash
# 统一入口：选择 BSP 目标，再分派准备、构建、打包、运行和清理操作。
# 用法及各命令见 usage；工程说明见 doc/README.md。
# 任意阶段失败即停止；pipefail 保证 tee 写日志时仍传播构建失败。
set -eo pipefail

# ========== 1. 根据脚本位置定位工程，加载公共函数 ==========
# 不依赖调用者的当前目录，支持从工程之外执行入口脚本。
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "$SCRIPT_DIR/lib/bsp.sh"
usage() {
    cat <<'HELP'
用法: ./build.sh <vendor> <soc> <board> [命令] [--dry-run]
      ./build.sh list
命令:
  all          生成 br2-external，构建 U-Boot/内核/rootfs，然后打包（默认）
  prepare      仅生成基于符号链接的 br2-external
  configure    生成 br2-external 并加载 Buildroot 配置，不编译
  uboot        仅编译 U-Boot
  kernel       仅编译内核
  rootfs       仅编译 Buildroot rootfs
  menuconfig   打开 Buildroot 配置菜单
  pack         生成 QEMU 启动脚本及校验文件
  run          启动 QEMU（root 登录，空密码；Ctrl+A X 退出）
  test         启动 QEMU，验证登录、架构、网络接口并关机
  clean [uboot|kernel|rootfs|all]   清理所选目标或组件
环境变量: JOBS、KERNEL_CROSS_COMPILE、UBOOT_CROSS_COMPILE、ROOTFS_CROSS_COMPILE
示例: ./build.sh qemu arm64 virt all
      ./build.sh qemu arm64 virt all --dry-run
HELP
}
# ========== 2. 处理无需选定板子的帮助和目标列表 ==========
# 以实际存在的 boards/<vendor>/<soc>/<board>/bsp.mk 为目标清单。
case "${1:-}" in
    -h|--help|help|'') usage; exit ;;
    list)
        for config in "$SCRIPT_DIR/../boards/"*/*/*/bsp.mk; do
            [ -f "$config" ] || continue
            target=${config#"$SCRIPT_DIR/../boards/"}; target=${target%/bsp.mk}
            echo "${target//\// }"
        done
        exit ;;
esac
# ========== 3. 读取板级配置，检查命令参数，识别 dry-run ==========
# bsp_load 用 Make 解析 bsp.mk，同时确定当前目标的输出与日志目录。
bsp_load "${1:-}" "${2:-}" "${3:-}"
COMMAND=${4:-all}
if [ "$COMMAND" = clean ]; then
    [ "$#" -le 6 ] || bsp_die "参数过多"
    case "${6:-}" in ''|--dry-run) ;; *) bsp_die "未知参数 ${6}" ;; esac
else
    [ "$#" -le 5 ] || bsp_die "参数过多"
    case "${5:-}" in ''|--dry-run) ;; *) bsp_die "未知参数 ${5}" ;; esac
fi
DRY_RUN=
# dry-run 只读取配置并打印操作，不创建构建目录或删除产物。
if [ "$COMMAND" = --dry-run ]; then COMMAND=all; DRY_RUN=--dry-run; fi
if [ "${5:-}" = --dry-run ] || [ "${6:-}" = --dry-run ]; then DRY_RUN=--dry-run; fi
echo "DarkOS BSP: $VENDOR / $SOC / $BOARD — $COMMAND"
# ========== 4. 定义分组件调用及完整构建顺序 ==========
# 所有组件使用同一个目标；只有需要时才传递 --dry-run 参数。
stage() { "$SCRIPT_DIR/$1" "$VENDOR" "$SOC" "$BOARD" ${DRY_RUN:+"$DRY_RUN"}; }
build_all() {
    # 准备 external -> U-Boot -> 内核 -> rootfs -> QEMU 启动镜像。
    stage prepare-external.sh
    stage build-uboot.sh
    stage build-kernel.sh
    stage build-rootfs.sh
    [ "$VENDOR" != qemu ] || stage pack-qemu.sh
}
# ========== 5. 执行用户选择的操作 ==========
case "$COMMAND" in
    all)
        if [ -n "$DRY_RUN" ]; then build_all
        else
            # 完整流程额外保留总日志，各组件仍写自己的日志。
            mkdir -p "$LOGS_DIR"
            build_all 2>&1 | tee "$LOGS_DIR/build.log"
        fi
        ;;
    prepare) stage prepare-external.sh ;;
    configure) "$SCRIPT_DIR/build-rootfs.sh" "$VENDOR" "$SOC" "$BOARD" "${DRY_RUN:-configure}" ;;
    uboot) stage build-uboot.sh ;;
    kernel) stage build-kernel.sh ;;
    rootfs) stage build-rootfs.sh ;;
    menuconfig) "$SCRIPT_DIR/build-rootfs.sh" "$VENDOR" "$SOC" "$BOARD" "${DRY_RUN:-menuconfig}" ;;
    pack) stage pack-qemu.sh ;;
    run) stage run-qemu.sh ;;
    test)
        # 实测时由 Python 驱动串口登录；dry-run 仅展示启动参数。
        if [ -n "$DRY_RUN" ]; then stage run-qemu.sh
        else python3 "$SCRIPT_DIR/test-qemu.py" "$VENDOR" "$SOC" "$BOARD"; fi ;;
    clean)
        # all 删除当前目标目录；组件清理交给对应脚本。
        # 共享下载缓存 output/downloads 不在此清理范围内。
        component=${5:-all}
        if [ "$component" = --dry-run ]; then component=all; fi
        case "$component" in all|uboot|kernel|rootfs) ;; *) bsp_die "不支持的清理组件 $component" ;; esac
        if [ -n "$DRY_RUN" ]; then echo "将清理 ${OUTPUT_DIR#"$BSP_ROOT"/} ($component)"; exit; fi
        if [ "$component" = all ]; then rm -rf "$OUTPUT_DIR"
        else "$SCRIPT_DIR/build-$component.sh" "$VENDOR" "$SOC" "$BOARD" clean; fi ;;
    *) usage; bsp_die "不支持的命令 $COMMAND" ;;
esac
