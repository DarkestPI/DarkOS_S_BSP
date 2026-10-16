# RK3588S EVB1 的机器配置；公共构建策略和 RK3588S 默认值由上层加载。
include $(BSP_ROOT)/vendors/rockchip/rk3588s/bsp.mk

# 目标标识。
BSP_BOARD        := evb1
BSP_BOARD_NAME   := RK3588S EVB1
BSP_BOARD_VERSION := v1.0

# 内核使用本板 defconfig 和设备树；板级驱动选项在 kernel.fragment 追加。
BSP_DEFCONFIG        := evb1_rk3588s_defconfig
BSP_DEFCONFIG_FILE   := $(BOARD_DIR)/configs/evb1_rk3588s_defconfig
BSP_DTS_NAME         := rk3588s-evb1-v10
BSP_DTS_DIR          := $(BOARD_DIR)/dts
BSP_KERNEL_TARGETS   := Image rockchip/$(BSP_DTS_NAME).dtb

# U-Boot 沿用 SoC 层 generic-rk3588 共用目标（上游 defconfig 和设备树）。

BSP_BUILDROOT_DEFCONFIG      := darkos_evb1_defconfig
BSP_BUILDROOT_DEFCONFIG_FILE := $(BOARD_DIR)/configs/darkos_evb1_defconfig

BSP_IMAGE_FORMAT             := sdcard
BSP_BOOT_DTB                 := $(BSP_DTS_NAME).dtb
BSP_BOOT_PARTITION_START_MIB := 16
BSP_BOOT_PARTITION_SIZE_MIB  := 128
BSP_IMAGE_SIZE_MIB           := 512
BSP_ROOTFS_PARTUUID          := 614e0000-0000-4b53-8000-0000000000e1
# pack-rockchip.sh 追加 root=PARTUUID=...，避免依赖 initramfs 解析 LABEL。
BSP_KERNEL_CMDLINE := console=ttyS2,1500000n8 rootwait rw
