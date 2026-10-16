#!/bin/bash
# 调用目标配置的打包后端（BSP_PACK_SCRIPT）生成启动镜像及校验文件。
set -eo pipefail
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "$SCRIPT_DIR/../lib/bsp.sh"
bsp_load "${1:-}" "${2:-}" "${3:-}"
shift 3
DRY_RUN=
for option in "$@"; do
    case "$option" in
        --dry-run) [ -z "$DRY_RUN" ] || bsp_die "重复选项 $option"; DRY_RUN=--dry-run ;;
        *) bsp_die "未知参数 $option" ;;
    esac
done
backend=$(bsp_pack_backend)
[ -n "$backend" ] || bsp_die "此目标未配置 BSP_PACK_SCRIPT 打包后端"
[ -f "$backend" ] || bsp_die "找不到打包脚本 $backend"
bash "$backend" "$VENDOR" "$SOC" "$BOARD" ${DRY_RUN:+"$DRY_RUN"}
