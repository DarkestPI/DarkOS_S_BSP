# DarkOS QEMU ARM64 virt

最小启动链：`QEMU virt → U-Boot → Linux → BusyBox initramfs`。
内核和 U-Boot 使用 `sources/linux`、`sources/u-boot`；根文件系统使用
`sources/buildroot`。QEMU 自动生成 DTB，无需板级 DTS、TF-A 或原厂固件。
此目标使用内存中的 initramfs，关机后文件修改不会保留。

## 配置职责

`bsp.mk` 加载 `vendors/qemu/arm64/bsp.mk`，后者加载 QEMU 通用层及
`common/bsp.mk`。共享源码位置、自动选择工具链和并发数由公共层提供；
ARM64 层选择架构、工具链前缀及模拟器程序；本机器选择三套 defconfig、
CPU 型号、内存、CPU 数、加载地址和启动命令行。各层默认值使用 `?=`，
板级需要覆盖时使用 `:=`。

内核的基础配置位于 `configs/darkos_qemu_arm64_defconfig`。PSCI 和 SMP
由 ARM64 层提供；PL011 串口、Virtio 网络/块设备和 CPU 数上限由本目录的
`configs/kernel.fragment` 提供。统一构建入口会按层合并这些配置；只执行
基础 defconfig 并不包含全部机器设备配置。

共享 Linux、U-Boot 和 Buildroot 的版本由 Git 子模块提交锁定。本目录不再
重复记录源码版本、补丁路径、片段路径或输出目录。驱动及软件包以 Kconfig
和 Buildroot 配置为准。

## 构建和启动

在 BSP 根目录执行，也可以从其他目录用入口脚本的绝对路径执行：

```bash
./build.sh list
./build.sh qemu arm64 virt config
./build.sh qemu arm64 virt all --dry-run
./build.sh qemu arm64 virt all
./build.sh qemu arm64 virt test
./build.sh qemu arm64 virt run
```

`config` 只读显示继承后的 BSP 变量、实际源码目录和提交、补丁及配置片段，
不创建输出目录。修改公共层或机器层后，可以先用它核对最终选择。

登录名 `root`，空密码。本机 QEMU 串口按 `Ctrl+A`、`X` 退出；
也可以在 guest 中执行 `poweroff`。这是本地开发环境，QEMU 使用 user 网络，
默认没有对外开放 SSH、端口转发或远程登录服务。

镜像位于 `output/qemu_arm64_virt/images/`：

- `u-boot.bin`：QEMU BIOS。
- `Image`：ARM64 Linux 内核。
- `rootfs.cpio.gz`：BusyBox、glibc 和 BSP 配置组成的 initramfs。
- `boot.cmd` / `boot.scr`：包含实际 initramfs 大小的 U-Boot 启动脚本。
- `SHA256SUMS`：启动镜像校验值；更新组件后执行 `pack` 再启动。

默认用软件仿真，无需 KVM。默认 512 MiB 内存、2 个 CPU；可调整为：

```bash
QEMU_MEMORY=256 QEMU_CPUS=1 ./build.sh qemu arm64 virt run
```

## 分组件操作

```bash
./build.sh qemu arm64 virt prepare
./build.sh qemu arm64 virt configure
./build.sh qemu arm64 virt uboot
./build.sh qemu arm64 virt kernel
./build.sh qemu arm64 virt rootfs
./build.sh qemu arm64 virt menuconfig
./build.sh qemu arm64 virt pack
./build.sh qemu arm64 virt clean rootfs
./build.sh qemu arm64 virt clean all
```

`configure` 加载 Buildroot 配置但不编译；`menuconfig` 编辑 rootfs 配置。
Linux 和 U-Boot 的基线分别在本目录对应的 defconfig 中维护，机器驱动在
`kernel.fragment` 中维护。修改配置后再次构建对应组件会重新合并内核/U-Boot
配置；补丁或共享源码变化则先清理对应源码副本。

Buildroot 菜单修改保存在 `output/qemu_arm64_virt/rootfs/.config`。
后续构建保留菜单修改；修改板级 defconfig 时重新加载它。需要持久保存时执行：

```bash
make -C sources/buildroot O="$PWD/output/qemu_arm64_virt/rootfs" \
  BR2_DEFCONFIG="$PWD/boards/qemu/arm64/virt/configs/qemu_arm64_virt_defconfig" savedefconfig
```

工具链变更需要 `clean rootfs`；更新内核/U-Boot 源码或补丁后清理对应组件。
各组件输出的 `.darkos-source` 记录实际源码路径和提交；没有该记录的历史
输出也需要先清理对应组件再构建。QEMU 的 `run`/`test` 可以使用现有已打包
镜像，但构建时不会把没有来源记录的旧副本当成新源码的结果。
`clean kernel`、`clean uboot`、`clean rootfs` 仅清理该目标的相应组件；
其他板子的输出和共享下载缓存不会删除。

## 工具链和依赖

需要 Bash、GNU Make、主机 GCC/G++、rsync、patch、bison、flex、Python 3、
pkg-config、OpenSSL 开发库、wget/curl、cpio、unzip、file、bc 和
`qemu-system-aarch64`。Buildroot 的依赖检查会提示缺少的工具。

QEMU 目标会从 PATH、`/usr/bin` 和 `/opt` 的常见工具链目录选择可用的
AArch64 Linux GCC。当前源码要求 Linux GCC ≥ 8.1，ARM U-Boot GCC ≥ 10。
根文件系统模板采用外部 glibc 工具链；自动检测其 GCC 和 Linux headers
版本，并写入输出目录中的 `rootfs.defconfig`。工具链的 headers 版本
应按工具链本身填写，不需要等于运行内核版本。

可以明确选择三个独立的工具链；前缀需要包含最后的 `-`：

```bash
JOBS=4 \
KERNEL_CROSS_COMPILE=/path/to/kernel-toolchain/bin/aarch64-linux-gnu- \
UBOOT_CROSS_COMPILE=/path/to/uboot-toolchain/bin/aarch64-linux-gnu- \
ROOTFS_CROSS_COMPILE=/path/to/rootfs-toolchain/bin/aarch64-linux-gnu- \
./build.sh qemu arm64 virt all
```

其他原厂平台可以在自身 `bsp.mk` 中使用 `BSP_KERNEL_CROSS_COMPILE`、
`BSP_UBOOT_CROSS_COMPILE` 和 `BSP_ROOTFS_CROSS_COMPILE`。
对于使用 musl/uClibc、内部工具链或复杂原厂 SDK 的平台，应编写对应的
Buildroot defconfig，并在目标配置中设置 `BSP_ROOTFS_EXTERNAL_AUTO := n`，
覆盖公共层的默认自动检测策略。

首次 Buildroot 构建需要下载依赖并检查其 hash；共享缓存位于
`output/downloads/`，也可通过 `BR2_DL_DIR` 指定已有缓存。
各组件日志位于 `output/qemu_arm64_virt/logs/`；自动测试串口日志为
`qemu-test.log`。

## 已验证的组合

- U-Boot 2026.10：GCC 12.3。
- Linux 6.18.55：GCC 12.3。
- Buildroot 2026.08 / BusyBox 1.38.0：GCC 7.5，工具链 headers 4.10。
- QEMU 6.2：512 MiB / 2 CPU，以及 256 MiB / 1 CPU。
- 实测 root 登录、DHCP、`darkos-info`、正常关机；内核约 7.8 MiB，
  压缩 rootfs 约 2.6 MiB。

入口回归测试：`python3 scripts/tests/test-bsp.py`。
覆盖 external 链接、dry-run、分组件清理、未知参数及构建失败传播。

## 基于符号链接的 br2-external

每个目标独立生成自己的 external tree，不修改 Buildroot 源码：

```text
output/qemu_arm64_virt/br2-external/
├── external.desc                 # name: DARKOS
├── Config.in                     # 仅引用实际存在的 Kconfig
├── external.mk                   # 引入各层 package/*.mk
├── configs/
│   └── qemu_arm64_virt_defconfig -> 板级 rootfs defconfig
└── layers/
    ├── common -> common/
    ├── vendor -> vendors/qemu/common/
    ├── soc    -> vendors/qemu/arm64/
    └── board  -> boards/qemu/arm64/virt/
```

链接使用相对路径。配置、软件包和 overlay 保持在原来的 BSP 层中，
无需复制后再次维护。各层按 common → vendor → SoC → board 加载；
同名 overlay 文件由后面的层覆盖。新包需要在该层的 `packages/Config.in`
中声明；包的 `.mk` 会被自动引入。各层使用不同包名，避免重复定义。

Kconfig 和 Make 引用链接层时使用 `BR2_EXTERNAL_DARKOS_PATH`，例如：

```text
source "$BR2_EXTERNAL_DARKOS_PATH/layers/common/packages/foo/Config.in"
```

`common/packages/darkos-bsp-info` 是可运行的示例包，guest 中执行
`darkos-info` 可查看目标和内核信息。

## 启动内存布局

QEMU RAM 起点为 `0x40000000`，DTB 由 QEMU 提供给 U-Boot。
generic loader 将启动脚本放在 `0x41000000`，内核放在 `0x42000000`，
initramfs 放在 `0x48000000`。U-Boot 执行 `source 0x41000000`，随后
通过 `booti` 启动 Linux，并使用 U-Boot 的 `fdtcontroladdr`。
打包脚本检查镜像大小，避免镜像区域重叠。
