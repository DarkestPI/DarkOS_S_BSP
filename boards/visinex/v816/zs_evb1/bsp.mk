# visinex v816 zs_evb1 的机器配置；公共构建策略和芯片默认值由上层加载。
# 使用方法：复制 board-template 为 boards/visinex/v816/zs_evb1/，全文替换
# visinex/v816/zs_evb1 占位符（目录名只能含字母、数字、下划线和连字符）。
include $(BSP_ROOT)/vendors/visinex/v816/bsp.mk

# 目标标识。
BSP_BOARD         := zs_evb1
BSP_BOARD_NAME    := Visinex ZS-EVB1
BSP_BOARD_VERSION := v1.0

# 内核：本板 defconfig 与设备树；板级驱动选项在 configs/kernel.fragment 追加。
# defconfig 从 configs/board_defconfig 改名复制而来，通常保持极简即可。
# QEMU 类无设备树目标可删去 DTS 两行，BSP_KERNEL_TARGETS 只留 Image。
BSP_DEFCONFIG      := zs_evb1_defconfig
BSP_DEFCONFIG_FILE := $(BOARD_DIR)/configs/zs_evb1_defconfig
BSP_DTS_NAME       := v816-zs_evb1
BSP_DTS_DIR        := $(BOARD_DIR)/dts
BSP_KERNEL_TARGETS := Image visinex/$(BSP_DTS_NAME).dtb

# U-Boot（可选覆盖）：默认用芯片层 defconfig 和上游设备树；本板有独立设备树时
# 取消注释，写法参考 boards/rockchip/rk3588s/lubancat-4/bsp.mk。
# BSP_UBOOT_DEFCONFIG      := zs_evb1_uboot_defconfig
# BSP_UBOOT_DEFCONFIG_FILE := $(BOARD_DIR)/configs/zs_evb1_uboot_defconfig
# BSP_UBOOT_DTS_NAME       := $(BSP_DTS_NAME)
# BSP_UBOOT_DTS_DIR        := $(BOARD_DIR)/dts

# Buildroot：板级 defconfig，从 configs/darkos_board_defconfig 改名复制而来。
BSP_BUILDROOT_DEFCONFIG      := darkos_zs_evb1_defconfig
BSP_BUILDROOT_DEFCONFIG_FILE := $(BOARD_DIR)/configs/darkos_zs_evb1_defconfig

# 打包（可选）：厂商层配置了 BSP_PACK_SCRIPT 时按需覆盖布局参数；
# Rockchip SD 卡写法参考 boards/rockchip/rk3588s/lubancat-4/bsp.mk，
# QEMU 资源/地址参数参考 boards/qemu/arm64/virt/bsp.mk。
# BSP_IMAGE_FORMAT             := sdcard
# BSP_BOOT_DTB                 := $(BSP_DTS_NAME).dtb
# BSP_BOOT_PARTITION_START_MIB := 16
# BSP_BOOT_PARTITION_SIZE_MIB  := 128
# BSP_IMAGE_SIZE_MIB           := 512
# BSP_ROOTFS_PARTUUID          := 614e0000-0000-4b53-8000-00000000xxxx
# BSP_KERNEL_CMDLINE           := console=ttyS0,115200n8 rootwait rw
