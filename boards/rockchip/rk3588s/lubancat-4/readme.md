# LubanCat-4 / RK3588S

这是本工程第一款实板的最小启动基线：主线 U-Boot → 主线 Linux → Buildroot BusyBox/glibc 根文件系统，首先从 SD 卡启动到串口终端。软件编译检查不能代替真机启动测试；目前未完成实板验证。

## 硬件版本与设备树来源

板厂将 LubanCat-4 定义为 RK3588S 系列开发板，但存在 CPU、PCB 和器件版本变更。实现前后请核对实物 PCB 编号/日期、芯片丝印、DDR 型号与容量、网口 PHY 型号和原理图版本。

本板独立设备树回移自 Linux 官方提交 `6d9430d58714909071853c0949cdc93756aa3ad4`（2026-07-29）：

[`arch/arm64/boot/dts/rockchip/rk3588s-lubancat-4.dts`](https://github.com/torvalds/linux/blob/6d9430d58714909071853c0949cdc93756aa3ad4/arch/arm64/boot/dts/rockchip/rk3588s-lubancat-4.dts)。保留原作者与 SPDX，仅增加来源注释；SoC 的 `rk3588s.dtsi` 从当前内核或 U-Boot 源码读取。本地没有复制 EVB 的电源与 GPIO 配置。

上游提交记录的测试板使用 Realtek RTL8211F PHY，并将网口描述为普通 Clause 22 PHY、`phy-mode = "rgmii"`。若实物使用其他 PHY 或新版 PCB，应先核对 RGMII 时序和驱动。当前内核片段明确启用 Realtek 驱动，尚未针对其他 PHY 验证。

[官方产品说明](https://doc.embedfire.com/linux/rk3588/quick_start/en/latest/quick_start/lubancat/lubancat4.html)与[硬件版本资料](https://doc.embedfire.com/lubancat-rk/hardware/ebf_lubancat_rk_hardware/zh/latest/board/ebf_lubancat_rk.html#lubancat4)列出了板卡硬件资源、原理图及变更通知。

## 配置分层

- `vendors/rockchip/rk3588s/configs/rk3588s_defconfig` 提供最小用户态启动基础，不使用完整多平台 ARM64 defconfig。
- 厂商片段启用 Rockchip pinctrl/GPIO、MMC、I2C、SPI；SoC 片段启用八核 CPU、SCMI 和温控。
- 本板内核片段内置 RK806 PMIC、RK8602/3 供电驱动、Realtek 网口、RTC、状态灯和 PWM 风扇。MMC、GPT、ext4 与串口也直接内置，挂载根文件系统不依赖模块或 initramfs。
- U-Boot 使用源码内置的 `generic-rk3588_defconfig`，板级片段改用本板 DTS，并启用 extlinux/ext4 启动与 RK806 供电驱动。RK8602/3 在启动初期保留原有电压，由 Linux 对应驱动接管。`rk3588s-lubancat-4-u-boot.dtsi` 复用主线的 SoC bootph/binman 定义。
- Buildroot 使用外部 glibc 工具链；工具链路径、GCC、headers 和 RPC 能力由构建脚本按实际安装版本检测。

第一阶段没有加入 GPU、NPU、视频编解码、摄像头、无线或桌面用户态组件；设备树保留上游外设描述，后续按功能逐项启用和测试。

## 构建与镜像

在工程根目录执行：

```bash
ROOTFS_CROSS_COMPILE=/opt/rv1126b-aarch64-toolchain/bin/aarch64-buildroot-linux-gnu- \
  ./scripts/build.sh rockchip rk3588s lubancat-4 all
```

示例使用本机已安装的外部工具链；在其他机器上按实际安装路径调整 `ROOTFS_CROSS_COMPILE`。

也可分别构建内核、U-Boot 和 rootfs，然后调用本目标的打包脚本。产物位于 `output/rockchip_rk3588s_lubancat-4/images/`。`vendors/rockchip/common/rkbin` 必须按主仓库记录的子模块提交初始化，构建 U-Boot 需要板级配置选择的 DDR v1.24 和 BL31 v1.56 文件。

SD 镜像为 512 MiB：BootROM 启动镜像从 LBA 64 开始；boot 分区从 16 MiB 开始，容量 128 MiB；rootfs 分区使用剩余空间。Buildroot 生成 256 MiB 的 ext4 文件系统。

boot 分区包含 `Image`、`rk3588s-lubancat-4.dtb` 和 `extlinux/extlinux.conf`。内核命令行使用 `console=ttyS2,1500000n8 rootwait rw`，打包脚本追加固定的 `root=PARTUUID=614e0000-0000-4b53-8000-000000000002`。

## 本机验证记录

2026-10-11 使用 `/opt/rv1126b-aarch64-toolchain/bin/aarch64-buildroot-linux-gnu-`（GCC 13.4.0）完成内核、U-Boot、Buildroot 根文件系统的实际编译与 SD 镜像打包，均正常退出。

| 产物 | 大小 |
| --- | --- |
| `Image` | 10,738,176 字节 |
| `rk3588s-lubancat-4.dtb` | 84,565 字节 |
| `u-boot-rockchip.bin` | 9,482,240 字节 |
| `rootfs.ext4` | 268,435,456 字节（256 MiB） |
| `sdcard.img` | 536,870,912 字节（512 MiB） |

检查了 GPT 分区起始扇区、分区容量与根分区 PARTUUID，读取 boot 文件系统确认 extlinux 路径和 `ttyS2,1500000n8` 命令行，六项 SHA256 校验全部通过。根文件系统中确认了保留串口波特率的 getty、`eth0` DHCP 配置和 `darkos-info`。工程 29 项测试及现有 QEMU 目标重打包、实际启动回归通过。

这些结果验证了本机编译、文件内容及打包流程；尚未在 LubanCat-4 实物上验证 DDR 初始化、启动、网口或外设。

## 首次真机启动

1. 核对 PCB/芯片/DDR/PHY 与上述参考基线，连接板厂定义的调试 UART 的 GND、TX、RX。
2. 串口终端设置 **1500000、8N1**，使用板厂规定的电平；BusyBox getty 保留内核设定的速率。
3. 检查生成的 SD 镜像和实际 SD 设备路径，再手动写入整卡镜像。工程构建和打包不会自动烧写 SD、eMMC 或 SPI。
4. 插入 SD 卡，按板厂正常启动流程供电。观察 DDR、SPL、BL31、U-Boot、内核和 BusyBox 的串口输出。
5. 到达终端后检查 `dmesg`、`mount`、`ip link`、`/sys/class/thermal/`，记录芯片/DDR/PHY 信息及启动日志，再验证网口和外围设备。

默认根文件系统为开发用串口登录环境，未配置 root 密码或 SSH 服务。现有 eMMC/SPI 启动固件可能改变 BootROM 启动介质选择；遇到无法从 SD 启动时，先按板厂文档核对启动优先级和恢复流程。


```bash
./build.sh rockchip rk3588s lubancat-4 kernel      # 只编内核
./build.sh rockchip rk3588s lubancat-4 uboot       # 只编 U-Boot
./build.sh rockchip rk3588s lubancat-4 rootfs      # 只编 rootfs
./build.sh rockchip rk3588s lubancat-4 pack        # 只重新打包镜像
./build.sh rockchip rk3588s lubancat-4 clean all   # 清理后全量重建（保留下载缓存）
JOBS=16 ./build.sh rockchip rk3588s lubancat-4 all # 提高并行数（板级默认 4）

```