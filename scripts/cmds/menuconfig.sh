#!/bin/bash
# menuconfig 是 rootfs 的配置类操作：转发给 cmds/rootfs.sh，交互后结束。
set -eo pipefail
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
exec "$SCRIPT_DIR/rootfs.sh" "${1:-}" "${2:-}" "${3:-}" menuconfig "${@:4}"
