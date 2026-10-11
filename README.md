# DarkOS S BSP

面向 QEMU 仿真和真实嵌入式板卡的 BSP 工程。配置分为工程公共层、厂商通用层、
SoC/架构层和板级层；各目标在 `output/<vendor>_<soc>_<board>/` 中独立构建。

当前主仓库维护构建脚本、配置、设备树、补丁和文档，四个 Git 子模块固定
Linux、U-Boot、Buildroot 和 Rockchip rkbin 的版本。详见
[工程说明](doc/README.md)、[Git 仓库管理](doc/git-management.md)和
[源码准备](doc/source.md)。

主仓库拉取后，在工程根目录初始化源码及固件：

```bash
git submodule update --init --recursive --depth 1
git submodule status
```

先查看目标及继承后的配置：

```bash
./build.sh list
./build.sh qemu arm64 virt config
./build.sh rockchip rk3588s lubancat-4 config
```

`config` 只读：显示最终 BSP 变量、实际源码路径和提交、补丁/片段及启动固件
路径，不创建输出目录。`bsp.mk` 使用 Makefile 语法；上层默认使用 `?=`，
下层按需覆盖。

QEMU ARM64 virt 是已完成启动验证的仿真目标，运行 U-Boot、Linux 和最小
BusyBox rootfs：

```bash
./build.sh qemu arm64 virt all
./build.sh qemu arm64 virt test
./build.sh qemu arm64 virt run
```

操作及配置保存方法见 [QEMU 板级说明](boards/qemu/arm64/virt/readme.md)。

首款真实板卡选择 **野火 LubanCat-4（RK3588S）**。当前基线沿用工程固定的
主线 Linux/U-Boot/Buildroot，回移上游板级设备树并使用固定 rkbin 启动固件，
提供串口、SD/eMMC 和有线网络的开发配置。图形、视频、NPU 与无线功能另行适配；
真实硬件启动和外设状态以板上测试为准。

```bash
./build.sh rockchip rk3588s lubancat-4 all --dry-run
./build.sh rockchip rk3588s lubancat-4 all
```

Rockchip 的打包步骤生成普通 SD 镜像文件，不自动向设备烧写。固件版本、分区
布局和开发步骤见 [LubanCat-4 板级说明](boards/rockchip/rk3588s/lubancat-4/readme.md)。
原 `rockchip rk3588s evb1` 仍是历史占位目标，不代表 LubanCat-4 的配置或验证结果。
