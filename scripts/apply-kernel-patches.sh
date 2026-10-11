#!/bin/bash
# 用法: ./scripts/apply-patches.sh <vendor> <soc> <board>

set -e

VENDOR=$1
SOC=$2
BOARD=$3

BSP_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
KERNEL_DIR="$BSP_ROOT/sources/linux"

# 补丁层叠顺序（从通用到具体）
PATCH_DIRS=(
    "$BSP_ROOT/common/patches/linux"
    "$BSP_ROOT/vendors/$VENDOR/common/patches/linux"
    "$BSP_ROOT/vendors/$VENDOR/$SOC/patches/linux"
    "$BSP_ROOT/boards/$VENDOR/$SOC/$BOARD/patches/linux"
)

echo "=== 应用内核补丁 ==="
for dir in "${PATCH_DIRS[@]}"; do
    if [ -d "$dir" ]; then
        echo "--- 层: $dir"
        for patch in $(ls "$dir"/*.patch 2>/dev/null | sort); do
            echo "    应用: $(basename "$patch")"
            git -C "$KERNEL_DIR" am "$patch" || {
                echo "    冲突! 请手动解决: $patch"
                exit 1
            }
        done
    fi
done

echo "=== 所有内核补丁应用完成 ==="