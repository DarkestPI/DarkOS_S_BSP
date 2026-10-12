# 厂商层与 SoC 层

厂商目录保存跨板卡共享的配置、片段、补丁和包；具体机器的设备连接、
供电、存储布局和组件配置选择位于 `boards/`。

```text
common/bsp.mk
  → vendors/<vendor>/common/bsp.mk
  → vendors/<vendor>/<soc>/bsp.mk
  → boards/<vendor>/<soc>/<board>/bsp.mk
```

工程公共层维护共享源码位置和构建策略；厂商通用层维护平台共用约定和打包
后端；SoC 层维护架构、芯片驱动和启动固件要求；板级层维护真实硬件差异。
上层默认使用 `?=`，下层按需覆盖。补丁、配置片段和 rootfs overlay 按相同
顺序叠加；没有实际共享内容时无需创建空片段或重复默认值。

QEMU 的第二层标识 `arm64` 是架构，`virt` 是机器。Rockchip 的 `rk3588s`
是芯片，`lubancat-4` 是实际板卡。能力由内核/Buildroot 配置和硬件验证决定，
单独设置描述用 `BSP_FEATURE_*` 不会启用驱动或安装软件包。

可通过只读命令核对最终选择：

```bash
./build.sh qemu arm64 virt config
./build.sh rockchip rk3588s lubancat-4 config
```

## QEMU

当前完整仿真目标为 `qemu arm64 virt`。层级约定见
[QEMU 厂商说明](qemu/readme.md)，运行方法见
[virt 板级说明](../boards/qemu/arm64/virt/readme.md)。

## Rockchip 瑞芯微

当前真实硬件开发目标为 `rockchip rk3588s lubancat-4`，具体配置见
[LubanCat-4 板级说明](../boards/rockchip/rk3588s/lubancat-4/readme.md)。
启动固件由 `vendors/rockchip/common/rkbin` 中的官方子模块提供，
供 Rockchip 各 SoC 和板卡共享；板级功能按阶段验证。

- [官网](https://www.rock-chips.com/)
- [开源社区](https://opensource.rock-chips.com/)
- [官方 Linux/U-Boot/固件仓库](https://github.com/rockchip-linux)
- [RKNN 等用户态组件](https://github.com/airockchip)

## Allwinner 全志

预留厂商目录，尚未接通完整板级目标。

- [官网](https://www.allwinnertech.com/)
- [开发者社区](https://www.aw-ol.com/)
- [linux-sunxi 社区](https://linux-sunxi.org/)

## Visinex 为旌

预留厂商目录，尚未接通完整板级目标。

- [官网](https://www.visinextek.com/)
