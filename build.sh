#!/bin/bash
# 工程根目录入口：把全部参数交给 scripts/build.sh。
# exec 使退出码和中断信号直接对应实际构建进程。
exec "$(dirname "$0")/scripts/build.sh" "$@"
