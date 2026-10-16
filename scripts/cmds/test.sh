#!/bin/bash
# 启动 QEMU 实测：验证串口登录、架构和网络接口后自动关机。
# --dry-run 只展示启动参数，复用 cmds/run.sh。
set -eo pipefail
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
if [ "${4:-}" = --dry-run ]; then
    exec "$SCRIPT_DIR/run.sh" "$@"
fi
exec python3 "$SCRIPT_DIR/../test-qemu.py" "$@"
