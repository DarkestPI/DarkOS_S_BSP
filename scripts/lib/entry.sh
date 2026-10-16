#!/bin/bash
# 入口参数解析：分离目标、命令和透传选项。
# 命令即文件：cmds/<命令>.sh 存在即支持，不存在即报错并列出全部可用命令。

# 解析 ./build.sh <vendor> <soc> <board> [命令] [选项...]。
# help/list 无需选定板子，就地执行后退出；其余命令设置全局变量待 run_command 分派。
entry_parse() {
    case "${1:-}" in
        -h|--help|help|'') exec "$SCRIPT_DIR/cmds/help.sh" ;;
        list) exec "$SCRIPT_DIR/cmds/list.sh" ;;
    esac
    VENDOR=${1:-} SOC=${2:-} BOARD=${3:-}
    shift 3
    COMMAND=all
    if [ "$#" -gt 0 ] && [[ "$1" != --* ]]; then COMMAND=$1; shift; fi
    ENTRY_OPTIONS=("$@")
    [ -f "$SCRIPT_DIR/cmds/$COMMAND.sh" ] ||
        bsp_die "未知命令 $COMMAND；可用命令: $(entry_list_commands)"
}

# 按解析结果调用命令脚本；目标名和剩余选项原样透传。
run_command() {
    exec "$SCRIPT_DIR/cmds/$COMMAND.sh" "$VENDOR" "$SOC" "$BOARD" "${ENTRY_OPTIONS[@]}"
}

# 命令表来自 cmds/ 目录内容，新增命令放入文件即自动可用。
entry_list_commands() {
    (cd "$SCRIPT_DIR/cmds" && ls -1 *.sh 2>/dev/null | sed 's/\.sh$//' | tr '\n' ' ')
}
