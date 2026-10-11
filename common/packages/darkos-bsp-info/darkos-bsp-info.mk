################################################################################
# darkos-bsp-info：通过 br2-external 公共层链接引入的本地示例包
################################################################################
# 1. 从 BSP 公共层同步包文件，不从网络下载此包。
DARKOS_BSP_INFO_VERSION = 1.0
DARKOS_BSP_INFO_SITE = $(BR2_EXTERNAL_DARKOS_PATH)/layers/common/packages/darkos-bsp-info
DARKOS_BSP_INFO_SITE_METHOD = local
DARKOS_BSP_INFO_LICENSE = MIT
DARKOS_BSP_INFO_LICENSE_FILES = LICENSE

# 2. 安装 guest 命令，并将总入口传来的目标名写入 rootfs/etc。
define DARKOS_BSP_INFO_INSTALL_TARGET_CMDS
	$(INSTALL) -D -m 0755 $(@D)/darkos-info $(TARGET_DIR)/usr/bin/darkos-info
	printf 'DarkOS BSP\nTarget: %s\n' '$(DARKOS_BSP_TARGET)' > $(TARGET_DIR)/etc/darkos-bsp-release
endef

# 3. 注册为 Buildroot 普通包，由 Config.in 控制是否启用。
$(eval $(generic-package))
