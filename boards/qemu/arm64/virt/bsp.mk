# =============================================================================
# bsp.mk - 板级构建描述文件
# 位置: boards/qemu/arm64/virt/bsp.mk
# 说明: 定义该板子的构建变量，供 scripts/ 下的构建脚本读取
# =============================================================================

# 加载 QEMU ARM64 默认配置，以下板级配置可覆盖默认值
include $(BSP_ROOT)/vendors/qemu/arm64/bsp.mk

# -----------------------------------------------------------------------------
# 1. 板级标识
# -----------------------------------------------------------------------------
BSP_VENDOR          := qemu
BSP_SOC             := arm64
BSP_BOARD           := virt
BSP_BOARD_NAME      := QEMU ARM64 virt
BSP_BOARD_VERSION   := v1.0

# -----------------------------------------------------------------------------
# 2. 架构与工具链
# -----------------------------------------------------------------------------
BSP_ARCH            := arm64
BSP_CROSS_COMPILE   := aarch64-linux-gnu-
BSP_JOBS            := 4

# 自动选择满足各构建组件最低版本要求的 AArch64 工具链
# 可通过 KERNEL_CROSS_COMPILE / UBOOT_CROSS_COMPILE / ROOTFS_CROSS_COMPILE 覆盖
BSP_TOOLCHAIN_AUTO  := y

# -----------------------------------------------------------------------------
# 3. 内核配置
# -----------------------------------------------------------------------------
BSP_KERNEL_VERSION      := v6.18.55
BSP_KERNEL_BRANCH       := linux-6.18.y
BSP_KERNEL_REPO         := https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git

# defconfig 文件名（会被复制到 arch/arm64/configs/ 下）
BSP_DEFCONFIG           := darkos_qemu_arm64_defconfig
# defconfig 文件在 BSP 仓库中的路径
BSP_DEFCONFIG_FILE      := $(BOARD_DIR)/configs/darkos_qemu_arm64_defconfig
# 最小环境只构建内核 Image，设备树由 QEMU 在启动时提供
BSP_KERNEL_TARGETS      := Image

# QEMU 自动生成设备树，不使用板级 DTS 文件
BSP_DTS_NAME            :=
BSP_DTS_DIR             :=

# -----------------------------------------------------------------------------
# 4. U-Boot 配置
# -----------------------------------------------------------------------------
BSP_UBOOT_VERSION       := v2026.10
BSP_UBOOT_BRANCH        := main
BSP_UBOOT_REPO          := https://git.u-boot-project.org/u-boot/u-boot.git
BSP_UBOOT_DEFCONFIG     := darkos_qemu_arm64_defconfig
BSP_UBOOT_DEFCONFIG_FILE := $(BOARD_DIR)/configs/darkos_qemu_arm64_uboot_defconfig

# -----------------------------------------------------------------------------
# 5. Buildroot 配置
# -----------------------------------------------------------------------------
BSP_BUILDROOT_VERSION        := 2026.08
BSP_BUILDROOT_BRANCH         := 2026.08.x
BSP_BUILDROOT_REPO           := https://git.buildroot.net/buildroot
BSP_BUILDROOT_DEFCONFIG      := qemu_arm64_virt_defconfig
BSP_BUILDROOT_DEFCONFIG_FILE := $(BOARD_DIR)/configs/qemu_arm64_virt_defconfig

# 自动检测外部 glibc 工具链的路径、GCC、headers 和语言支持能力
BSP_ROOTFS_EXTERNAL_AUTO     := y

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
#    构建脚本会按此顺序依次合并到 .config，跳过不存在的片段
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
# QEMU 从内存加载镜像，不需要物理分区表或烧录工具配置
BSP_PARTITION_TABLE     :=
BSP_FLASH_CONFIG        :=
# 根文件系统格式，配合 u-boot.bin、Image 和 boot.scr 启动
BSP_IMAGE_FORMAT        := cpio.gz

# -----------------------------------------------------------------------------
# 9. 板级特性开关（可选，供脚本判断）
# -----------------------------------------------------------------------------
BSP_FEATURE_NPU         := n
BSP_FEATURE_GPU         := n
BSP_FEATURE_VPU         := n
BSP_FEATURE_WIFI        := n
BSP_FEATURE_BT          := n
BSP_FEATURE_HDMI        := n
BSP_FEATURE_MIPI_DSI    := n
BSP_FEATURE_NETWORK     := y
BSP_FEATURE_VIRTIO      := y
BSP_FEATURE_QEMU        := y

# -----------------------------------------------------------------------------
# 10. 输出目录命名规则（脚本会用到）
# -----------------------------------------------------------------------------
BSP_OUTPUT_NAME         := $(BSP_VENDOR)_$(BSP_SOC)_$(BSP_BOARD)
BSP_OUTPUT_DIR          := $(BSP_ROOT)/output/$(BSP_OUTPUT_NAME)
BSP_IMAGES_DIR          := $(BSP_OUTPUT_DIR)/images

# -----------------------------------------------------------------------------
# 11. QEMU 运行配置
# -----------------------------------------------------------------------------
BSP_QEMU_BINARY         := qemu-system-aarch64
BSP_QEMU_CPU            := cortex-a57
# 内存单位为 MiB，CPU 数量不超过内核配置的 CONFIG_NR_CPUS
BSP_QEMU_MEMORY         := 512
BSP_QEMU_CPUS           := 2

# generic loader 加载地址：脚本、内核和 initramfs 使用独立的内存区域
BSP_QEMU_SCRIPT_ADDR    := 0x41000000
BSP_QEMU_KERNEL_ADDR    := 0x42000000
BSP_QEMU_INITRD_ADDR    := 0x48000000
BSP_KERNEL_CMDLINE      := console=ttyAMA0 rdinit=/init panic=5
