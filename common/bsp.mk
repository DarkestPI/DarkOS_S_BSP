# DarkOS 共享构建默认值。架构、芯片及板子选择由下层配置负责。
BSP_TOOLCHAIN_AUTO       ?= y
BSP_JOBS                 ?= 12
BSP_ROOTFS_EXTERNAL_AUTO ?= y

# 主仓库子模块固定源码提交；这些字段用于说明，不自动切换 checkout。
BSP_KERNEL_SOURCE_DIR    ?= $(BSP_ROOT)/sources/linux
BSP_KERNEL_VERSION       ?= v6.18.55
BSP_KERNEL_BRANCH        ?= linux-6.18.y
BSP_KERNEL_REPO          ?= https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git

BSP_UBOOT_SOURCE_DIR     ?= $(BSP_ROOT)/sources/u-boot
BSP_UBOOT_VERSION        ?= v2026.10
BSP_UBOOT_BRANCH         ?= master
BSP_UBOOT_REPO           ?= https://git.u-boot-project.org/u-boot/u-boot.git

BSP_BUILDROOT_SOURCE_DIR ?= $(BSP_ROOT)/sources/buildroot
BSP_BUILDROOT_VERSION    ?= 2026.08
BSP_BUILDROOT_BRANCH     ?= 2026.08.x
BSP_BUILDROOT_REPO       ?= https://gitlab.com/buildroot.org/buildroot.git

# 可选 OP-TEE 用户态支持。源码存在不等于安全世界已加载，默认不编入 rootfs。
# optee_os 留作 BL32 适配源码；当前脚本仅支持构建原生 optee-client 包。
BSP_OPTEE_CLIENT_ENABLE     ?= n
BSP_OPTEE_CLIENT_SOURCE_DIR ?= $(BSP_ROOT)/sources/optee_client
BSP_OPTEE_OS_SOURCE_DIR     ?= $(BSP_ROOT)/sources/optee_os
# 描述用版本号：OS 基线滞后于上游，client 与上游最新正式版一致（见 doc/security.md）。
BSP_OPTEE_OS_VERSION        ?= 4.9.0
BSP_OPTEE_CLIENT_VERSION    ?= 4.10.0
