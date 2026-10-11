# QEMU ARM64 架构默认值；virt 的 CPU 型号、资源和设备由板级选择。
include $(BSP_ROOT)/vendors/qemu/common/bsp.mk

BSP_ARCH          ?= arm64
BSP_CROSS_COMPILE ?= aarch64-linux-gnu-
BSP_QEMU_BINARY   ?= qemu-system-aarch64
