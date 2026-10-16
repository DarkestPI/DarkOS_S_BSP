#!/bin/bash
# 显示四层合并后的最终配置、分区布局和源码选择，并把快照写入
# output/<目标>/bsp.config；--dry-run 只显示，不写快照。
set -eo pipefail
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "$SCRIPT_DIR/../lib/bsp.sh"
bsp_load "${1:-}" "${2:-}" "${3:-}"
DRY_RUN=
for option in "${@:4}"; do
    case "$option" in
        --dry-run) [ -z "$DRY_RUN" ] || bsp_die "重复选项 $option"; DRY_RUN=--dry-run ;;
        *) bsp_die "未知参数 $option" ;;
    esac
done
bsp_print_config
