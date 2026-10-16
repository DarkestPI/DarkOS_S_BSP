#!/bin/bash
# configure 是 rootfs 的配置类操作：转发给 cmds/rootfs.sh，不编译。
set -eo pipefail
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
exec "$SCRIPT_DIR/rootfs.sh" "${1:-}" "${2:-}" "${3:-}" configure "${@:4}"
