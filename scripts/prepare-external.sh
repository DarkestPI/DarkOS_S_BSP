#!/bin/bash
# 用法: prepare-external.sh <vendor> <soc> <board> [--dry-run]
# 只生成 Buildroot external tree，实际链接规则由公共函数实现。
set -eo pipefail

# ========== 1. 加载目标配置及输出目录 ==========
source "$(dirname "$0")/lib/bsp.sh"
bsp_load "${1:-}" "${2:-}" "${3:-}"
# ========== 2. dry-run 仅展示目标路径，不创建链接 ==========
if [ "${4:-}" = --dry-run ]; then
    echo "将生成 ${BR2_EXT#"$BSP_ROOT"/}，以符号链接接入 common/vendor/soc/board"
    exit
fi
# ========== 3. 生成描述文件、Kconfig/Make 入口及各层相对符号链接 ==========
bsp_prepare_external
