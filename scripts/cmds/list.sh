#!/bin/bash
# 列出全部可用目标；以实际存在的 boards/<vendor>/<soc>/<board>/bsp.mk 为准。
SCRIPT_DIR=$(cd "$(dirname "$0")" && pwd)
for config in "$SCRIPT_DIR/../../boards/"*/*/*/bsp.mk; do
    [ -f "$config" ] || continue
    target=${config#"$SCRIPT_DIR/../../boards/"}
    target=${target%/bsp.mk}
    echo "${target//\// }"
done
