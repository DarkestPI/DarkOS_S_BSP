include $(BSP_ROOT)/vendors/rockchip/rk3588s/bsp.mk

BSP_BOARD := lubancat-4
BSP_BOARD_NAME := EmbedFire LubanCat-4
# 后续按实物 PCB 丝印确认具体硬件修订版。
BSP_BOARD_VERSION := upstream-reference

BSP_DTS_NAME := rk3588s-lubancat-4
BSP_DTS_DIR := $(BOARD_DIR)/dts
BSP_KERNEL_TARGETS := Image rockchip/$(BSP_DTS_NAME).dtb

# generic-rk3588 共用启动目标来自 SoC 层，设备树在板级片段中改为本板。
BSP_UBOOT_DTS_NAME := $(BSP_DTS_NAME)
BSP_UBOOT_DTS_DIR := $(BOARD_DIR)/dts

BSP_BUILDROOT_DEFCONFIG := darkos_lubancat_4_defconfig
BSP_BUILDROOT_DEFCONFIG_FILE := $(BOARD_DIR)/configs/darkos_lubancat_4_defconfig

BSP_IMAGE_FORMAT := sdcard
BSP_BOOT_DTB := $(BSP_DTS_NAME).dtb
BSP_BOOT_PARTITION_START_MIB := 16
BSP_BOOT_PARTITION_SIZE_MIB := 128
BSP_IMAGE_SIZE_MIB := 512
BSP_ROOTFS_PARTUUID := 614e0000-0000-4b53-8000-000000000002
# pack-rockchip.sh 追加 root=PARTUUID=...，避免依赖 initramfs 解析 LABEL。
BSP_KERNEL_CMDLINE := console=ttyS2,1500000n8 rootwait rw
