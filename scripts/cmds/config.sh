#!/bin/bash
# 选配置一步完成：生成目标专属 br2-external（符号链接接入四层），
# 显示合并后的最终配置和分区布局，并把快照写入 output/<目标>/bsp.config。
# --dry-run 只显示将执行的操作，不创建 external、不写快照。
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
# 先搭好 br2-external，再展示在此基础上解析出的最终配置。
if [ -n "$DRY_RUN" ]; then
    echo "将生成 ${BR2_EXT#"$BSP_ROOT"/}，以符号链接接入 generic/vendor/soc/board"
else
    mkdir -p "$OUTPUT_DIR"
    bsp_prepare_external
fi
bsp_print_config
