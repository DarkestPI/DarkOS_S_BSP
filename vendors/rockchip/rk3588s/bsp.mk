include $(BSP_ROOT)/vendors/rockchip/common/bsp.mk

BSP_SOC ?= rk3588s
BSP_ARCH ?= arm64
BSP_CROSS_COMPILE ?= aarch64-linux-gnu-

# 当前基线使用 common/bsp.mk 和源码子模块锁定的主线版本。
BSP_DEFCONFIG ?= darkos_rk3588s_defconfig
BSP_DEFCONFIG_FILE ?= $(BSP_ROOT)/vendors/rockchip/rk3588s/configs/rk3588s_defconfig

BSP_UBOOT_DEFCONFIG ?= generic-rk3588_defconfig
BSP_UBOOT_REQUIRE_BL31 ?= y
BSP_UBOOT_REQUIRE_TPL ?= y
# RK3588S 使用 rk3588 命名的固件；DDR 类型/布线仍需按实板验证。
BSP_UBOOT_BL31 ?= $(BSP_ROOT)/sources/rkbin/bin/rk35/rk3588_bl31_v1.56.elf
BSP_UBOOT_TPL ?= $(BSP_ROOT)/sources/rkbin/bin/rk35/rk3588_ddr_lp4_2112MHz_lp5_2400MHz_v1.24.bin
BSP_UBOOT_BL31_SHA256 ?= 2864c2fc36333e03e7e3fe6459225d320d310850b4ac7620d1f3601efb7d4a9b
BSP_UBOOT_TPL_SHA256 ?= 2853a0da7ab895af43d50615af73eccf0694115dd0202483ee1c93c9071a42c3
BSP_UBOOT_EXTRA_IMAGES ?= u-boot-rockchip.bin
