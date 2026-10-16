# DarkOS S BSP

面向 QEMU 仿真和真实嵌入式板卡的 BSP 工程。配置分为工程公共层、厂商通用层、
SoC/架构层和板级层；各目标在 `output/<vendor>_<soc>_<board>/` 中独立构建。

当前主仓库维护构建脚本、配置、设备树、补丁和文档，四个 Git 子模块固定
Linux、U-Boot、Buildroot 和 Rockchip rkbin 的版本。前三者位于 `sources/`，
rkbin 位于 `vendors/rockchip/common/rkbin`，供 Rockchip 各目标共享。详见
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

三个组件也可独立构建，默认自动判断增量或全量并打印原因：

```bash
./build.sh rockchip rk3588s lubancat-4 uboot
./build.sh rockchip rk3588s lubancat-4 kernel
./build.sh rockchip rk3588s lubancat-4 rootfs
./build.sh rockchip rk3588s lubancat-4 kernel --full --dry-run
./build.sh rockchip rk3588s lubancat-4 pack
```

`--full` 强制所选组件全量，`--incremental` 在输入不兼容时拒绝复用旧输出。
具体规则、清理范围和脚本职责见 [scripts 说明](scripts/README.md)。

Rockchip 的打包步骤生成普通 SD 镜像文件，不自动向设备烧写。固件版本、分区
布局和开发步骤见 [LubanCat-4 板级说明](boards/rockchip/rk3588s/lubancat-4/readme.md)。
原 `rockchip rk3588s evb1` 仍是历史占位目标，不代表 LubanCat-4 的配置或验证结果。










1. 基于 buildroot 工具构建；

2. 可以构建 Uboot、kernel buildroot 构建的文件系统、Ubuntu、Debian、等；

# 构建过程

## step1： 校验配置文件

- 第一阶段：build.sh 入口（scripts/build.sh）

这一步校验bsp.mk，校验流程优先级如下

```text
boards/qemu/arm64/virt/bsp.mk          （板级）
  └─ include vendors/qemu/arm64/bsp.mk      （SoC 厂商层）
       └─ include vendors/qemu/common/bsp.mk   （厂商公共层）
            └─ include common/bsp.mk              （工程公共层）
```

公共基础层：common/bsp.mk

soc 厂商 vendors 层：

vendors/<vendor>/<soc>/bsp.mk -> vendors/<vendor>/common/bsp.mk

板级厂商 boards 层：

boards/<vendor>/<soc>/<board>/bsp.mk








## Supported Systems

The Buildroot OS cross-compiler can target any Linux-compatible device or virtual machine. These system configuration packages are available in the main SkiffOS repository:

| **System**            | **Config Package**        | **Bootloader**   | **Kernel**      |
|-----------------------|---------------------------|------------------|-----------------|
| VirtualBox            | [virt/virtualbox]         | N/A              | ✔ 7.2.10       |
| [Docker Img]          | [virt/docker]             | N/A              | N/A             |
| [Qemu]                | [virt/qemu]               | N/A              | ✔ 7.2.10       |
|-----------------------|---------------------------|------------------|-----------------|
| [lubancat-4]          | [rk3588s/lubancat-4]      | ✔ U-boot 2022.10 | ✔ sm-6.1-rc3    |
| [walnutpi_2]          | [t527/walnutpi_2]         | ✔ U-Boot 2025.01 | ✔ 7.2.10       |
| [BananaPi M1]         | [bananapi/m1]             | ✔ U-Boot 2025.01 | ✔ 7.2.10       |

[lubancat-4]: https://doc.embedfire.com/linux/rk356x/quick_start/zh/latest/quick_start/lubancat/lubancat4.html
[walnutpi_2]: https://wiki.walnutpi.com/docs/walnutpi_2/

[rk3588s/lubancat-4]: ./boards/rockchip/rk3588s/lubancat-4/
[t527/walnutpi_2]: ./boards/allwinner/t527/walnutpi_2/

## Getting started

[Buildroot dependencies] must be installed as a prerequisite, assuming apt:

```
sudo apt-get install -y \
  bash \
  bc \
  binutils \
  build-essential \
  bzip2 \
  cpio \
  diffutils \
  file \
  findutils \
  git \
  gzip \
  libarchive-tools \
  libncurses-dev \
  make \
  patch \
  perl \
  rsync \
  sed \
  tar \
  unzip \
  wget
```

[Buildroot dependencies]: https://buildroot.org/downloads/manual/manual.html#requirement-mandatory
