#!/bin/bash
# 清理所选目标：clean [uboot|kernel|rootfs|all]。
# all 删除当前目标输出目录；组件清理交给对应 cmds/<组件>.sh；
# 共享下载缓存 output/downloads 不在清理范围。
set -eo pipefail
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "$SCRIPT_DIR/../lib/bsp.sh"
bsp_load "${1:-}" "${2:-}" "${3:-}"
shift 3
DRY_RUN=
component=all
component_seen=n
for option in "$@"; do
    case "$option" in
        --dry-run) [ -z "$DRY_RUN" ] || bsp_die "重复选项 $option"; DRY_RUN=--dry-run ;;
        all|uboot|kernel|rootfs)
            [ "$component_seen" = n ] || bsp_die "重复组件 $option"
            component=$option; component_seen=y ;;
        *) bsp_die "未知参数 $option" ;;
    esac
done
if [ -n "$DRY_RUN" ]; then
    echo "将清理 ${OUTPUT_DIR#"$BSP_ROOT"/} ($component)"
    exit
fi
if [ "$component" = all ]; then rm -rf "$OUTPUT_DIR"
else "$SCRIPT_DIR/$component.sh" "$VENDOR" "$SOC" "$BOARD" clean; fi
