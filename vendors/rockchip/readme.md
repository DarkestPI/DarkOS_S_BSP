# Rockchip 厂商层

这里保存可在 Rockchip 板卡间复用的构建约定、配置片段和芯片启动固件选择。第一款实板目标是 `rockchip / rk3588s / lubancat-4`。

配置按 `common/bsp.mk → vendors/rockchip/common/bsp.mk → vendors/rockchip/rk3588s/bsp.mk → boards/rockchip/rk3588s/lubancat-4/bsp.mk` 加载。共享默认值使用 `?=`，板级差异使用 `:=`。现有 `evb1` 是独立参考板目录，不能作为 LubanCat-4 的设备树使用。

| 层级 | 内容 |
| --- | --- |
| `rockchip/common` | rkbin 启动固件子模块、BootROM 镜像偏移、打包入口、Rockchip 通用 pinctrl/GPIO/时钟/MMC 驱动 |
| `rockchip/rk3588s` | 最小 ARM64 内核配置、八核 CPU/SCMI/温控片段、DDR 与 BL31 文件选择 |
| `boards/rockchip/rk3588s/lubancat-4` | PMIC、网口 PHY、板级设备树、串口、根文件系统与 SD 分区布局 |

当前选择本工程已固定的主线 Linux 6.18.55、U-Boot 2026.10 和 Buildroot 2026.08，配合 `vendors/rockchip/common/rkbin` 子模块中的原厂 DDR/BL31 二进制。源码版本实际由 Git 子模块提交锁定；`BSP_*_VERSION` 字段不自动切换源码。

RK3588S 在主线 U-Boot 中使用 `CONFIG_ROCKCHIP_RK3588`，启动固件采用 `rk3588_*` 文件名。当前组合为 DDR `rk3588_ddr_lp4_2112MHz_lp5_2400MHz_v1.24.bin` 和 BL31 `rk3588_bl31_v1.56.elf`。DDR v1.20 起新增双通道支持时要求 BL31 至少 v1.53，所选组合满足这一版本要求；这不替代具体 DDR 型号、板卡版本和硬件启动验证。

固件来自 rkbin 固定提交 `3e288fe814e059dd06833495f845cab04ac20a5c`，SHA256 记录在 SoC 的 `bsp.mk`。本板参考配置为 LPDDR4X；选择的二进制名称包含 lp4/lp5，不意味着不需要核对实际内存与板卡。

参考资料：

- [U-Boot 官方 Rockchip 构建说明](https://docs.u-boot.org/en/latest/board/rockchip/rockchip.html)
- [rkbin 官方 RK3588 发布记录](https://github.com/rockchip-linux/rkbin/blob/master/doc/release/RK3588_EN.md)
- [板厂公开内核](https://github.com/LubanCat/kernel)、[U-Boot](https://github.com/LubanCat/u-boot)、[SDK manifest](https://github.com/LubanCat/manifests)

板厂 SDK 的设备树、GPU/视频/NPU 用户态组件和主线接口可能不同。引入这些功能时应建立单独的源码版本/补丁与运行库配置，不能直接把厂商 defconfig 混入本主线基线。
