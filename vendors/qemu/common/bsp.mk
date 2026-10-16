# QEMU 平台默认值；源码、工具链自动选择和并发数由工程公共层提供。
include $(BSP_ROOT)/generic/bsp.mk

# QEMU 从内存启动，打包后端生成 U-Boot 脚本及镜像校验文件。
BSP_PACK_SCRIPT ?= $(BSP_ROOT)/scripts/pack-qemu.sh
