# <vendor> <soc> 芯片层：维护架构、工具链和芯片级配置基线；板卡差异在 boards/。
# 使用方法：把 soc/ 目录复制改名为 <soc>/，全文替换 <vendor>/<soc> 占位符。
include $(BSP_ROOT)/vendors/<vendor>/common/bsp.mk

BSP_SOC ?= <soc>
BSP_ARCH ?= arm64
BSP_CROSS_COMPILE ?= aarch64-linux-gnu-

# 芯片参考内核 defconfig（可选）：无板级覆盖的目标使用；
# 板级用 := 指向自己的 BSP_DEFCONFIG/BSP_DEFCONFIG_FILE 覆盖。
# BSP_DEFCONFIG ?= <vendor>_<soc>_defconfig
# BSP_DEFCONFIG_FILE ?= $(BSP_ROOT)/vendors/<vendor>/<soc>/configs/<vendor>_<soc>_defconfig

# U-Boot defconfig（可选）：不设置时默认使用上游 defconfig，板级可覆盖。
# BSP_UBOOT_DEFCONFIG ?= <vendor>_<soc>_defconfig

# 启动固件（可选）：需要原厂 BL31/TPL 等固件的芯片在此声明路径和校验值，
# 写法参考 vendors/rockchip/rk3588s/bsp.mk 的 BSP_UBOOT_BL31/BSP_UBOOT_TPL。
