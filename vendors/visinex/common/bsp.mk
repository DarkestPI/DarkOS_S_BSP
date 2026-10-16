# visinex 厂商公共层：维护本厂商各芯片/板卡共用约定；芯片差异在 soc/ 层。
# 使用方法：复制 vendor-template 为 vendors/visinex/，全文替换 visinex 占位符。
include $(BSP_ROOT)/generic/bsp.mk

BSP_VENDOR ?= visinex

# 打包后端（可选）：配置后 all 会在构建完成后调用它生成启动镜像。
# 新平台可参考 scripts/pack-qemu.sh 或 scripts/pack-rockchip.sh 编写。
# BSP_PACK_SCRIPT ?= $(BSP_ROOT)/scripts/pack-visinex.sh
