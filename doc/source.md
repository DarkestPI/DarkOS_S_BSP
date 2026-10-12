# 源码和启动固件准备

本工程使用 Git 子模块固定可复现的源码组合，初始化时优先使用主仓库记录的
提交，而不是跟随上游分支：

```bash
git submodule sync --recursive
git submodule update --init --recursive --depth 1
git submodule status
```

四个目录分别是 `sources/linux`、`sources/u-boot`、`sources/buildroot` 和
`vendors/rockchip/common/rkbin`。前三者为当前固定的主线源码；rkbin 为瑞芯微
官方发布的启动固件仓库，放在 Rockchip 厂商通用层供各 SoC 和板卡共享，
其中 DDR 初始化等组件以二进制提供。加入 rkbin 不会把内核或
U-Boot 切换为原厂 SDK。

`--depth 1` 减少历史下载，源码文件仍完整。主仓库中的 gitlink 决定实际提交，
`common/bsp.mk` 中的版本说明不会执行下载或 checkout。升级方式见
[Git 仓库管理](git-management.md)。

## 查看实际使用的版本

```bash
./build.sh qemu arm64 virt config
./build.sh rockchip rk3588s lubancat-4 config
```

该命令同时显示继承后的配置和各源码目录的实际 Git 提交。没有独立 Git
元数据时显示为 `unversioned`；有 Git 元数据但无法解析提交时显示为 `unknown`。

## 为目标选择另一套已有源码

`common/bsp.mk` 提供默认目录；厂商、SoC 或板级配置可以设置：

```make
BSP_KERNEL_SOURCE_DIR := $(BSP_ROOT)/sources/linux-rockchip
BSP_UBOOT_SOURCE_DIR := $(BSP_ROOT)/sources/u-boot-rockchip
BSP_BUILDROOT_SOURCE_DIR := $(BSP_ROOT)/sources/buildroot
```

也可以通过组件环境变量临时覆盖；相对目录以工程根目录为基准：

```bash
KERNEL_SOURCE_DIR=sources/linux-rockchip \
  ./build.sh rockchip rk3588s lubancat-4 config
```

`KERNEL_SOURCE_DIR`、`UBOOT_SOURCE_DIR`、`BUILDROOT_SOURCE_DIR` 优先于对应
`BSP_*_SOURCE_DIR`。这只选择已有目录；内核版本、驱动、设备树、片段、固件及
用户态组件是否兼容仍需一起核对。切换源码目录或提交后，先清理对应组件的
源码副本再构建，不要把旧副本当成新源码的构建结果。

## 手工取得一份浅克隆

仅在另外准备源码目录时使用；不要覆盖已初始化的子模块。以下命令只取得指定
版本的当前源码，不下载全部分支历史：

```bash
git clone --depth 1 --single-branch --no-tags --branch v6.18.55 \
  https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git \
  /path/to/linux

git clone --depth 1 --single-branch --no-tags --branch v2026.10 \
  https://git.u-boot-project.org/u-boot/u-boot.git \
  /path/to/u-boot

git clone --depth 1 --single-branch --no-tags --branch 2026.08 \
  https://gitlab.com/buildroot.org/buildroot.git \
  /path/to/buildroot
```

Rockchip 内核公开仓库为 [rockchip-linux/kernel](https://github.com/rockchip-linux/kernel)，
启动固件仓库为 [rockchip-linux/rkbin](https://github.com/rockchip-linux/rkbin)。
厂商内核是一种可选择的源码基线；下载整个厂商 SDK 与克隆单个公开内核仓库
是不同操作，本工程不自动同步受控 SDK 仓库。
