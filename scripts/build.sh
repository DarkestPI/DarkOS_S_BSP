#!/bin/bash
# DarkOS BSP 构建入口。
#
# 本文件不做任何具体工作，只完成三件事：
#   1. 按脚本位置定位工程；
#   2. 加载公共库和参数解析（lib/entry.sh）；
#   3. 把命令交给 cmds/<命令>.sh 执行。
#
# 命令一览——cmds/ 目录一命令一文件，目录即命令表：
#   all(默认) list help
#   prepare configure menuconfig uboot kernel rootfs
#   config pack run test clean
# 详细用法：./build.sh help
set -eo pipefail

SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
source "$SCRIPT_DIR/lib/bsp.sh"
source "$SCRIPT_DIR/lib/entry.sh"

entry_parse "$@"    # 解析 <vendor> <soc> <board> [命令] [选项]；help/list 就地完成
run_command         # 执行 cmds/$COMMAND.sh <vendor> <soc> <board> [选项]
