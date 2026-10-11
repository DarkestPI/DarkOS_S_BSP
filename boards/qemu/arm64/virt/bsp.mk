# QEMU virt 的机器配置；公共构建策略和 ARM64 默认值由上层加载。
include $(BSP_ROOT)/vendors/qemu/arm64/bsp.mk

# 目标标识。
BSP_VENDOR        := qemu
BSP_SOC           := arm64
BSP_BOARD         := virt
BSP_BOARD_NAME    := QEMU ARM64 virt
BSP_BOARD_VERSION := v1.0

# 组件配置均由本目标选择；内核设备配置来自按层合并的 fragment。
BSP_DEFCONFIG               := darkos_qemu_arm64_defconfig
BSP_DEFCONFIG_FILE          := $(BOARD_DIR)/configs/darkos_qemu_arm64_defconfig
BSP_KERNEL_TARGETS          := Image
BSP_UBOOT_DEFCONFIG         := darkos_qemu_arm64_defconfig
BSP_UBOOT_DEFCONFIG_FILE    := $(BOARD_DIR)/configs/darkos_qemu_arm64_uboot_defconfig
BSP_BUILDROOT_DEFCONFIG     := qemu_arm64_virt_defconfig
BSP_BUILDROOT_DEFCONFIG_FILE := $(BOARD_DIR)/configs/qemu_arm64_virt_defconfig

# QEMU 自动生成 DTB；此机器不提供板级 DTS 或物理分区/烧录配置。
BSP_DTS_NAME :=
BSP_DTS_DIR  :=

# virt 的 CPU 型号和资源；CPU 数量不得超过 kernel.fragment 的 NR_CPUS。
BSP_QEMU_CPU    := cortex-a57
BSP_QEMU_MEMORY := 512
BSP_QEMU_CPUS   := 2

# U-Boot、Image 和 initramfs 的加载地址由本机器的 RAM 布局决定。
BSP_QEMU_SCRIPT_ADDR := 0x41000000
BSP_QEMU_KERNEL_ADDR := 0x42000000
BSP_QEMU_INITRD_ADDR := 0x48000000
BSP_KERNEL_CMDLINE   := console=ttyAMA0 rdinit=/init panic=5
