# =============================================================================
# bsp.mk - 板级构建描述文件
# 位置: boards/rockchip/rk3588s/evb1/bsp.mk
# 说明: 定义该板子的构建变量，供 scripts/ 下的构建脚本读取
# =============================================================================

# -----------------------------------------------------------------------------
# 1. 板级标识
# -----------------------------------------------------------------------------
BSP_VENDOR          := rockchip
BSP_SOC             := rk3588s
BSP_BOARD           := evb1
BSP_BOARD_NAME      := RK3588S EVB1
BSP_BOARD_VERSION   := v1.0

# -----------------------------------------------------------------------------
# 2. 架构与工具链
# -----------------------------------------------------------------------------
BSP_ARCH            := arm64
BSP_CROSS_COMPILE   := aarch64-linux-gnu-
BSP_JOBS            := 16

# -----------------------------------------------------------------------------
# 3. 内核配置
# -----------------------------------------------------------------------------
BSP_KERNEL_VERSION      := v6.18.55
BSP_KERNEL_BRANCH       := linux-6.18.y
BSP_KERNEL_REPO         := https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git

# defconfig 文件名（会被复制到 arch/arm64/configs/ 下）
BSP_DEFCONFIG           := evb1_rk3588s_defconfig
# defconfig 文件在 BSP 仓库中的路径
BSP_DEFCONFIG_FILE      := $(BOARD_DIR)/configs/evb1_rk3588s_defconfig

# 设备树名称（不带 .dts 后缀，用于输出镜像命名）
BSP_DTS_NAME            := rk3588s-evb1
# 设备树文件在 BSP 仓库中的目录
BSP_DTS_DIR             := $(BOARD_DIR)/dts

# -----------------------------------------------------------------------------
# 4. U-Boot 配置
# -----------------------------------------------------------------------------
BSP_UBOOT_VERSION       := v2026.10
BSP_UBOOT_BRANCH        := main
BSP_UBOOT_REPO          := https://git.u-boot-project.org/u-boot/u-boot.git
BSP_UBOOT_DEFCONFIG     := evb1-rk3588s_defconfig
BSP_UBOOT_DEFCONFIG_FILE := $(BOARD_DIR)/configs/evb1-rk3588s_defconfig

# -----------------------------------------------------------------------------
# 5. Buildroot 配置
# -----------------------------------------------------------------------------
BSP_BUILDROOT_VERSION   := 2026.08
BSP_BUILDROOT_BRANCH    := 2026.08.x
BSP_BUILDROOT_REPO      := https://git.buildroot.net/buildroot
BSP_BUILDROOT_DEFCONFIG := rockchip_rk3588s_evb1_defconfig

# -----------------------------------------------------------------------------
# 6. 补丁层叠顺序（从通用到具体）
#    构建脚本会按此顺序依次应用补丁
# -----------------------------------------------------------------------------
BSP_PATCH_DIRS_LINUX := \
    $(BSP_ROOT)/common/patches/linux \
    $(BSP_ROOT)/vendors/$(BSP_VENDOR)/common/patches/linux \
    $(BSP_ROOT)/vendors/$(BSP_VENDOR)/$(BSP_SOC)/patches/linux \
    $(BOARD_DIR)/patches/linux

BSP_PATCH_DIRS_UBOOT := \
    $(BSP_ROOT)/common/patches/uboot \
    $(BSP_ROOT)/vendors/$(BSP_VENDOR)/common/patches/uboot \
    $(BSP_ROOT)/vendors/$(BSP_VENDOR)/$(BSP_SOC)/patches/uboot \
    $(BOARD_DIR)/patches/uboot

# -----------------------------------------------------------------------------
# 7. 配置片段层叠顺序（从通用到具体）
#    构建脚本会按此顺序依次合并到 .config
# -----------------------------------------------------------------------------
BSP_FRAGMENTS_LINUX := \
    $(BSP_ROOT)/common/configs/common.fragment \
    $(BSP_ROOT)/vendors/$(BSP_VENDOR)/common/configs/$(BSP_VENDOR).fragment \
    $(BSP_ROOT)/vendors/$(BSP_VENDOR)/$(BSP_SOC)/configs/$(BSP_SOC).fragment \
    $(BOARD_DIR)/configs/kernel.fragment

BSP_FRAGMENTS_UBOOT := \
    $(BSP_ROOT)/common/configs/uboot.fragment \
    $(BSP_ROOT)/vendors/$(BSP_VENDOR)/common/configs/uboot.fragment \
    $(BSP_ROOT)/vendors/$(BSP_VENDOR)/$(BSP_SOC)/configs/uboot.fragment \
    $(BOARD_DIR)/configs/uboot.fragment

# -----------------------------------------------------------------------------
# 8. 烧录与打包
# -----------------------------------------------------------------------------
# 分区表文件（如果有）
BSP_PARTITION_TABLE     := $(BOARD_DIR)/configs/parameter.txt
# 烧录工具配置（如 Rockchip 的 config.ini）
BSP_FLASH_CONFIG        := $(BOARD_DIR)/scripts/flash_config.ini
# 镜像输出格式: img / wic / sdcard
BSP_IMAGE_FORMAT        := img

# -----------------------------------------------------------------------------
# 9. 板级特性开关（可选，供脚本判断）
# -----------------------------------------------------------------------------
BSP_FEATURE_NPU         := y
BSP_FEATURE_GPU         := y
BSP_FEATURE_VPU         := y
BSP_FEATURE_WIFI        := y
BSP_FEATURE_BT          := y
BSP_FEATURE_HDMI        := y
BSP_FEATURE_MIPI_DSI    := y

# -----------------------------------------------------------------------------
# 10. 输出目录命名规则（脚本会用到）
# -----------------------------------------------------------------------------
BSP_OUTPUT_NAME         := $(BSP_VENDOR)_$(BSP_SOC)_$(BSP_BOARD)
BSP_OUTPUT_DIR          := $(BSP_ROOT)/output/$(BSP_OUTPUT_NAME)
BSP_IMAGES_DIR          := $(BSP_OUTPUT_DIR)/images