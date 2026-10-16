################################################################################
# OP-TEE 的本地服务钩子：复用 Buildroot 原生包，不注册同名包或重复编译 client。
################################################################################
ifeq ($(BR2_PACKAGE_DARKOS_OPTEE_CLIENT_SERVICE),y)
define DARKOS_OPTEE_INSTALL_GUARDED_SERVICE
	$(INSTALL) -D -m 0755 \
		$(BR2_EXTERNAL_DARKOS_PATH)/layers/common/packages/optee-local/S30tee-supplicant \
		$(TARGET_DIR)/etc/init.d/S30tee-supplicant
endef

# 原生包的 SysV 安装步骤之后执行；关闭 client 时不会安装或启动服务。
OPTEE_CLIENT_POST_INSTALL_TARGET_HOOKS += DARKOS_OPTEE_INSTALL_GUARDED_SERVICE
endif
