# Rockchip 厂商共用约定；具体芯片和板卡覆盖各自的差异。
include $(BSP_ROOT)/common/bsp.mk

BSP_VENDOR ?= rockchip
# BootROM 的 SD/eMMC 启动镜像位于 LBA 64（512 字节扇区）。
BSP_BOOTLOADER_OFFSET_SECTORS ?= 64
BSP_BOOTLOADER_IMAGE ?= u-boot-rockchip.bin
BSP_PACK_SCRIPT ?= $(BSP_ROOT)/scripts/pack-rockchip.sh
