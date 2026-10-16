#!/bin/bash
# 完整构建流水线。
#   2.1 编译 bootloader、内核、根文件系统
#   2.2 打包启动镜像
#   2.3 打包升级包（可选，预留）
#   2.4 生成报告（可选，预留）
set -eo pipefail
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "$SCRIPT_DIR/../lib/bsp.sh"
bsp_load "${1:-}" "${2:-}" "${3:-}"
shift 3

# 解析构建模式与演练选项，构造转发给各组件的公共参数。
MODE=auto
DRY_RUN=
for option in "$@"; do
    case "$option" in
        --dry-run) [ -z "$DRY_RUN" ] || bsp_die "重复选项 $option"; DRY_RUN=--dry-run ;;
        --full|--incremental)
            [ "$MODE" = auto ] || bsp_die "--full 和 --incremental 只能选择一个，且不能重复"
            MODE=${option#--} ;;
        *) bsp_die "未知参数 $option" ;;
    esac
done
ARGS=()
[ "$MODE" = auto ] || ARGS+=("--$MODE")
[ -z "$DRY_RUN" ] || ARGS+=("--dry-run")

pipeline() {
    # ---------- 2.1 编译 bootloader、内核、根文件系统 ----------
    "$SCRIPT_DIR/prepare.sh" "$VENDOR" "$SOC" "$BOARD" "${ARGS[@]}"
    "$SCRIPT_DIR/uboot.sh"   "$VENDOR" "$SOC" "$BOARD" "${ARGS[@]}"
    "$SCRIPT_DIR/kernel.sh"  "$VENDOR" "$SOC" "$BOARD" "${ARGS[@]}"
    "$SCRIPT_DIR/rootfs.sh"  "$VENDOR" "$SOC" "$BOARD" "${ARGS[@]}"
    # ---------- 2.2 打包启动镜像 ----------
    if [ -n "${BSP_PACK_SCRIPT:-}" ]; then
        "$SCRIPT_DIR/pack.sh" "$VENDOR" "$SOC" "$BOARD" ${DRY_RUN:+"$DRY_RUN"}
    fi
    # ---------- 2.3 打包升级包（可选）：预留挂接点，尚未实现 ----------
    # ---------- 2.4 生成报告（可选）：预留挂接点；images/ 已含 SHA256SUMS ----------
}

# 完整流程额外保留总日志，各组件仍写自己的日志。
if [ -n "$DRY_RUN" ]; then
    pipeline
else
    mkdir -p "$LOGS_DIR"
    pipeline 2>&1 | tee "$LOGS_DIR/build.log"
fi
