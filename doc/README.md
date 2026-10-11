# DarkOS S BSP 工程说明

本文说明当前工程的组织方式、构建流程、配置约定和操作方法。
工程根目录的 `build.sh` 是统一入口，目标通过 `vendor / soc / board` 三个参数选择。

当前源码管理与版本锁定见 [Git 仓库管理](git-management.md)。
未来多平台扩展的候选方案见 [repo 多仓库管理方案](repo-management.md)。

## 1. 当前工程状态

当前已完整构建并启动验证的目标是 `qemu arm64 virt`：

```text
QEMU virt → U-Boot → Linux → initramfs /init → BusyBox init → root 登录
```

| 组件 | 当前源码/版本 | 已验证工具链 |
| --- | --- | --- |
| U-Boot | `sources/u-boot`，2026.10 | AArch64 GCC 12.3 |
| Linux | `sources/linux`，6.18.55 | AArch64 GCC 12.3 |
| Buildroot | `sources/buildroot`，2026.08 | 外部 AArch64 GCC 7.5 |
| BusyBox | Buildroot 下载并构建的 1.38.0 | 同 rootfs 工具链 |
| QEMU | 宿主机已有的 `qemu-system-aarch64`，6.2 | 不在本工程中编译模拟器本身 |

已验证 512 MiB / 2 CPU 和 256 MiB / 1 CPU 两种运行配置；测试包括
root 登录、AArch64 架构、`/proc`、本地 BSP 包、DHCP 和正常关机。
参考产物大小：内核约 7.8 MiB，压缩 rootfs 约 2.6 MiB。

`rockchip rk3588s evb1` 已有 `bsp.mk`、内核 defconfig 和 DTS 文件，
当前还没有补齐对应的 U-Boot 和 Buildroot defconfig，不能据此认为完整构建已通过。
其他 vendor/board 目录用于后续扩展。`manifest.xml`、CI 构建矩阵和测试矩阵
目前是占位文件，尚未接通源码同步或 CI 流程。

QEMU `virt` 是通用 ARM64 虚拟平台，不是 RK3588 的硬件模型。
它适合调试用户态程序、服务和通用内核功能，不能代替 RK3588 专有外设的真板验证。

## 2. 工程目录

```text
DarkOS_S_BSP/
├── build.sh                      # 根目录入口，转交 scripts/build.sh
├── scripts/                      # 构建、打包、运行及测试脚本
│   ├── lib/bsp.sh                # 配置、工具链、分层目录和复制等公共函数
│   └── tests/test-bsp.py          # 入口回归测试
├── sources/                      # 原始上游源码
│   ├── linux/
│   ├── u-boot/
│   └── buildroot/
├── common/                       # 各平台共用的配置、包、补丁和 overlay
│   └── packages/darkos-bsp-info/  # 本地示例包，安装 darkos-info
├── vendors/                      # vendor 通用层与 SoC/架构层
│   └── qemu/
│       ├── common/bsp.mk
│       └── arm64/bsp.mk
├── boards/                       # 最具体的板级配置
│   ├── qemu/arm64/virt/
│   └── rockchip/rk3588s/evb1/
├── output/                       # 各目标的源码副本、构建输出和下载缓存
│   ├── downloads/                # 共享的 Buildroot 下载缓存
│   └── qemu_arm64_virt/
├── doc/README.md                 # 本文
├── ci/                           # 预留 CI 目录
└── manifest.xml                  # 预留源码管理清单
```

每个目标的输出目录固定为 `output/<vendor>_<soc>_<board>/`：

| 子目录/文件 | 内容 |
| --- | --- |
| `kernel/` | 内核源码副本、补丁、板级文件和编译中间文件 |
| `uboot/` | U-Boot 源码副本、补丁、配置和编译中间文件 |
| `rootfs/` | Buildroot 的独立输出目录，由 `O=` 指定 |
| `rootfs/build/` | 依赖源码解包、补丁及编译目录 |
| `rootfs/host/` | 为构建准备的宿主工具及导入的工具链 |
| `rootfs/staging/` | 指向构建 sysroot 的链接，包含目标开发头文件和库 |
| `rootfs/target/` | rootfs 安装目录；不是可直接烧写的最终镜像 |
| `rootfs/images/` | Buildroot 生成的文件系统镜像 |
| `br2-external/` | 每个目标独立生成的 Buildroot 扩展树 |
| `rootfs.defconfig` | 根据板级模板和本机工具链生成的 Buildroot 配置 |
| `images/` | 汇总后的内核、U-Boot、rootfs 和启动文件 |
| `logs/` | 构建日志与 QEMU 串口测试日志 |

### 源码与输出隔离方式

内核和 U-Boot 保持现有的源码副本方案：首次构建从 `sources` 复制到当前目标的
`kernel/`、`uboot/`，之后在副本中应用补丁、复制板级文件并编译。
这样不同板子的源码修改互相隔离，也不会修改原始源码。

Buildroot 直接使用 `sources/buildroot`，以 `O=<目标目录>/rootfs` 指定输出目录。
它下载的第三方源码包保存到共享 `output/downloads`，解包和编译文件保存到
各目标的 `rootfs/build`。原始 Buildroot 源码无需复制。

Linux 和 U-Boot 自身也支持 `O=`；本工程目前采用源码副本，便于分别维护
各板子的补丁、DTS 和 defconfig。指定输出目录只能分离编译生成文件，
不会隔离直接对源码应用的补丁。

## 3. 开始使用

构建前需要准备 `sources/linux`、`sources/u-boot` 和 `sources/buildroot`。
从主仓库拉取工程后，执行 `git submodule update --init --recursive --depth 1`
初始化三个源码子模块，检出主仓库锁定的提交。
当前脚本使用已有源码，不自动 clone 或按 `bsp.mk` 中的版本切换 checkout。

宿主需要 Bash、GNU Make、GCC/G++、Python 3、rsync、patch、bison、flex、
pkg-config、OpenSSL 开发库、wget/curl、cpio、unzip、file、bc 等工具。
运行虚拟机还需要 `qemu-system-aarch64`。Buildroot 会检查其构建依赖。
首次 rootfs 构建需要访问源码下载站点；已有缓存可以复用。

在工程根目录执行：

```bash
./build.sh --help
./build.sh list
./build.sh qemu arm64 virt all --dry-run
./build.sh qemu arm64 virt all
./build.sh qemu arm64 virt test
./build.sh qemu arm64 virt run
```

脚本根据自身位置定位工程，也可以在其他工作目录使用入口的绝对路径。
`dry-run` 检查配置和工具链并展示操作，不正式构建、不创建输出目录、不清理文件。

QEMU 登录名为 `root`，空密码。按 `Ctrl+A` 后按 `X` 退出模拟器，或在 guest
中执行 `poweroff`。rootfs 是内存中的 initramfs，关机后修改不会保留。
默认使用软件仿真，无需 KVM；使用 user 网络，默认不配置 tap 或端口转发。

## 4. 统一入口和脚本分工

命令格式为：

```text
./build.sh <vendor> <soc> <board> [命令] [--dry-run]
```

未指定命令时执行 `all`。完整流程依次为：

1. `prepare-external.sh`：建立当前目标的 `br2-external` 相对符号链接和入口文件。
2. `build-uboot.sh`：准备副本、应用补丁、加载配置、编译并汇总 U-Boot。
3. `build-kernel.sh`：准备副本、应用补丁和 DTS、合并配置、编译并汇总内核。
4. `build-rootfs.sh`：生成工具链配置，调用 Buildroot，汇总 rootfs 镜像。
5. QEMU 目标调用 `pack-qemu.sh`：生成 `boot.scr` 和镜像校验文件。

任意阶段失败即停止；`set -e` 与 `pipefail` 使 `tee` 写日志时仍传播构建失败。

| 命令 | 功能 |
| --- | --- |
| `all` | 完整构建及 QEMU 打包 |
| `prepare` | 只建立 `br2-external` |
| `configure` | 生成 external 和 Buildroot 配置，可执行工具链能力探测，不正式编译组件 |
| `uboot` / `kernel` / `rootfs` | 构建单个组件 |
| `menuconfig` | 打开 Buildroot 交互配置菜单，不继续编译镜像 |
| `pack` | 对已有 QEMU 组件镜像重新打包 |
| `run` | 校验镜像后启动 QEMU，不执行编译 |
| `test` | 用串口自动登录、验证并关机 |
| `clean [组件]` | 清理当前目标的 `uboot`、`kernel`、`rootfs` 或全部输出 |

根目录入口用 `exec` 转交给 `scripts/build.sh`。后者解析命令，公共函数库
`scripts/lib/bsp.sh` 负责目标配置、工具链检查、文件层叠和 external 生成。
组件脚本也可以直接调用，例如：

```bash
./scripts/build-kernel.sh qemu arm64 virt --dry-run
./scripts/build-uboot.sh qemu arm64 virt
./scripts/build-rootfs.sh qemu arm64 virt configure
```

`scripts/apply-kernel-patches.sh` 是原有的独立辅助脚本，直接对 `sources/linux`
执行 `git am`。统一入口没有调用它；当前正式构建流程在源码副本中应用补丁。

## 5. 板级配置及分层约定

`boards/<vendor>/<soc>/<board>/bsp.mk` 使用 Makefile 语法，可以包含 `:=`、
`$(BOARD_DIR)` 和 `include`。公共函数通过 Make 展开 `BSP_*` 变量后逐项赋给
Bash；不能把这个文件作为普通 shell 文件直接 `source`。

QEMU 默认值按以下顺序加载：

```text
vendors/qemu/common/bsp.mk
    → vendors/qemu/arm64/bsp.mk
    → boards/qemu/arm64/virt/bsp.mk
```

板级 `bsp.mk` 分为标识、架构与工具链、内核、U-Boot、Buildroot、补丁、
配置片段、打包、特性、输出目录，以及 QEMU 专用运行参数等部分。

| 常用变量 | 作用 |
| --- | --- |
| `BSP_ARCH`、`BSP_CROSS_COMPILE`、`BSP_JOBS` | 架构、默认工具链前缀、并发数 |
| `BSP_DEFCONFIG`、`BSP_DEFCONFIG_FILE` | 内核配置目标和板级配置文件 |
| `BSP_KERNEL_TARGETS` | 内核 make 目标；QEMU 仅构建 `Image` |
| `BSP_UBOOT_DEFCONFIG`、`BSP_UBOOT_DEFCONFIG_FILE` | U-Boot 配置目标和文件 |
| `BSP_BUILDROOT_DEFCONFIG`、`BSP_BUILDROOT_DEFCONFIG_FILE` | rootfs 配置模板 |
| `BSP_TOOLCHAIN_AUTO` | 是否自动寻找满足版本要求的已安装工具链 |
| `BSP_ROOTFS_EXTERNAL_AUTO` | 是否自动检测并填写外部 glibc 工具链信息 |
| `BSP_QEMU_*`、`BSP_KERNEL_CMDLINE` | QEMU 运行资源、加载地址和内核命令行 |

`BSP_*_VERSION/BRANCH/REPO` 记录期望的源码信息，目前不会触发自动同步。
特性开关主要用于描述当前板子，不会自动启用对应驱动。
输出目录由统一入口按三个目标参数生成，`BSP_OUTPUT_*` 是相同规则的配置描述。

文件层级为 common → vendor common → SoC → board：

```text
common/
vendors/<vendor>/common/
vendors/<vendor>/<soc>/
boards/<vendor>/<soc>/<board>/
```

补丁从各层 `patches/linux/*.patch` 或 `patches/uboot/*.patch` 收集，同层按文件名
顺序应用。配置片段不存在时跳过；同一选项在后层重新定义时，后层值覆盖前层。
最终结果仍受 Kconfig 依赖约束。

Linux 片段依次是 `common.fragment`、`<vendor>.fragment`、`<soc>.fragment`、
板级 `kernel.fragment`；U-Boot 各层统一使用 `uboot.fragment`。
当前脚本按这些固定目录约定收集文件，`bsp.mk` 中的 `BSP_PATCH_DIRS_*` 和
`BSP_FRAGMENTS_*` 列表用于描述同一约定，单独修改列表不会改变脚本的收集逻辑。

## 6. 内核与 U-Boot 的构建步骤

两者先检查工具链，再在当前目标目录准备源码副本。已有副本会复用，
不自动同步后来对 `sources` 作出的修改。

补丁正向试运行成功时应用；反向试运行成功时认为已经应用；两个方向都失败
则停止。这样重复构建不会重复应用同一补丁。

内核会把板级 DTS 复制到副本的 `arch/<arch>/boot/dts/<vendor>/`，把 defconfig
复制到 `arch/<arch>/configs/`，执行 defconfig、片段合并和 `olddefconfig` 后编译。
QEMU 没有板级 DTS，设备树由模拟器在启动时提供。

U-Boot 把板级 defconfig 复制到副本的 `configs/`，生成 `.config`，合并可选
片段后编译。ARM64 内核使用 `ARCH=arm64`；ARM64 U-Boot 的实现位于
`arch/arm`，构建参数使用 `ARCH=arm`。

当前内核最低 GCC 版本从源码 `scripts/min-tool-version.sh` 读取，ARM64 为 8.1。
当前 U-Boot ARM 构建要求 GCC 至少 10；组件脚本允许用板级变量调整最低要求。

## 7. br2-external 与 rootfs 构建

每个目标单独生成 external tree：

```text
output/<目标>/br2-external/
├── external.desc                 # name: DARKOS
├── Config.in                     # source 实际存在的各层 Kconfig
├── external.mk                   # include 各层包配方
├── configs/<rootfs_defconfig>    # 指向板级模板的相对符号链接
└── layers/
    ├── common → 工程 common/
    ├── vendor → vendors/<vendor>/common/
    ├── soc    → vendors/<vendor>/<soc>/
    └── board  → boards/<vendor>/<soc>/<board>/
```

Buildroot 使用 external 名称生成 `BR2_EXTERNAL_DARKOS_PATH`。各层中的 Kconfig
和包配方通过此变量访问文件。维护时修改链接指向的 BSP 源文件，不修改生成的入口。

支持各层的 `packages/` 和 `package/` 目录。新增包需要在该层的 `Config.in`
入口中声明；`.mk` 配方会按约定自动引入。各层包名应唯一，当前没有同名包覆盖机制。

各层 `rootfs-overlay/` 按顺序传入 `BR2_ROOTFS_OVERLAY`，后层同名文件覆盖前层。
`common/packages/darkos-bsp-info` 提供本地示例：安装 `darkos-info`，并将当前
目标名写到 `/etc/darkos-bsp-release`。板级 `S99darkos` 在启动末尾打印准备完成信息。

rootfs 构建依次执行：

1. 读取板级 Buildroot defconfig，生成输出目录中的 `rootfs.defconfig`。
2. 自动模式下检测外部工具链路径、GCC、glibc 和 Linux headers。
3. 检测原生 RPC、C++、Fortran、D、OpenMP 能力，用实际值替换模板声明。
4. 追加各层 overlay 路径，按需加载生成配置。
5. 在 `rootfs/` 中构建依赖、导入工具链、安装目标程序并打包镜像。
6. 将 `rootfs/images/rootfs.*` 汇总到当前目标 `images/`。

`rootfs/.config` 是实际配置，`.darkos-defconfig` 记录上次加载的模板。
模板未改变时保留 `menuconfig` 修改；模板改变后重新加载。
已导入工具链后变更工具链配置，需要先清理 rootfs。

QEMU rootfs 不让 Buildroot 编译内核或 U-Boot；这两个组件由独立脚本构建。
内核与用户态可以使用不同工具链，用户态程序及库仍须匹配架构、ABI 和运行库。
外部工具链的 headers 版本按工具链本身填写，不要求等于运行内核版本。

### 配置菜单与保存

```bash
./build.sh qemu arm64 virt menuconfig
./build.sh qemu arm64 virt rootfs
./build.sh qemu arm64 virt pack
```

需要将菜单配置保存回板级模板时：

```bash
make -C sources/buildroot O="$PWD/output/qemu_arm64_virt/rootfs" \
  BR2_DEFCONFIG="$PWD/boards/qemu/arm64/virt/configs/qemu_arm64_virt_defconfig" savedefconfig
```

保存的内容可能包含本机工具链或输出目录路径，纳入共享配置前应检查。

## 8. 工具链和环境变量

组件工具链选择优先级：组件环境变量 → 组件板级变量 → 通用 `CROSS_COMPILE`
环境变量 → 通用 `BSP_CROSS_COMPILE`。

例如内核为 `KERNEL_CROSS_COMPILE` → `BSP_KERNEL_CROSS_COMPILE` →
`CROSS_COMPILE` → `BSP_CROSS_COMPILE`。
开启自动选择且没有显式组件或通用环境覆盖时，从候选路径选择第一个满足要求
的已安装 AArch64 GCC，不会下载工具链，也不保证选择最新版本。

| 环境变量 | 用途 |
| --- | --- |
| `JOBS` | 覆盖板级并发数，必须为正整数 |
| `KERNEL_CROSS_COMPILE` | 指定内核工具链前缀 |
| `UBOOT_CROSS_COMPILE` | 指定 U-Boot 工具链前缀 |
| `ROOTFS_CROSS_COMPILE` | 自动外部 glibc 配置模式下指定 rootfs 工具链前缀 |
| `CROSS_COMPILE` | 通用工具链前缀，优先使用组件专用覆盖 |
| `BR2_DL_DIR` | 指定共享下载缓存目录 |
| `QEMU_BINARY` / `QEMU_CPU` | 覆盖模拟器路径和 CPU 型号 |
| `QEMU_MEMORY` | 运行内存，单位 MiB，当前脚本要求至少 256 |
| `QEMU_CPUS` | CPU 数量，当前为 1～4 |
| `QEMU_TEST_TIMEOUT` | 自动测试总超时，默认 120 秒 |

工具链前缀包含最后的 `-`，例如：

```bash
JOBS=4 \
KERNEL_CROSS_COMPILE=/path/to/kernel-toolchain/bin/aarch64-linux-gnu- \
UBOOT_CROSS_COMPILE=/path/to/uboot-toolchain/bin/aarch64-linux-gnu- \
ROOTFS_CROSS_COMPILE=/path/to/rootfs-toolchain/bin/aarch64-linux-gnu- \
./build.sh qemu arm64 virt all
```

非自动模式使用 Buildroot defconfig 中的工具链配置。musl/uClibc、内部工具链或
复杂原厂 SDK 应编写自己的 defconfig，不启用 QEMU 的外部 glibc 自动配置逻辑。

## 9. QEMU 打包与启动

`pack` 要求已有 `u-boot.bin`、`Image` 和 `rootfs.cpio.gz`。
它使用 U-Boot 副本中编译出的宿主工具 `tools/mkimage`。

打包脚本检查镜像区域容量，按实际 initramfs 大小生成 `boot.cmd`，再添加
U-Boot 镜像头生成 `boot.scr`。其中 `booti` 使用启动时的 `fdtcontroladdr`，
把 QEMU 提供给 U-Boot 的设备树传给 Linux。

| 加载对象 | 地址 |
| --- | --- |
| QEMU RAM 起点 | `0x40000000` |
| `boot.scr` | `0x41000000` |
| `Image` | `0x42000000` |
| `rootfs.cpio.gz` | `0x48000000` |

`run` 使用 `-bios` 加载 U-Boot，generic loader 把其他三个文件写入上述内存地址。
U-Boot 自动执行 `source 0x41000000`，随后启动内核。
内核命令行包含 `console=ttyAMA0 rdinit=/init`；Buildroot 的 `/init` 先挂载
devtmpfs，再执行 BusyBox init。

`SHA256SUMS` 记录四个启动文件的校验值。单独更新组件后执行 `pack`，
否则启动前的校验会拒绝使用不一致的镜像集合。

```bash
QEMU_MEMORY=256 QEMU_CPUS=1 ./build.sh qemu arm64 virt run
```

## 10. 测试和日志

入口回归测试不需要正式编译组件：

```bash
python3 scripts/tests/test-bsp.py
```

它创建临时工程和模拟编译器，检查链接重复生成、Make 变量展开、dry-run、
分组件清理、未知参数拒绝、组件失败传播和完整流程提前停止。

实际启动测试需要已构建并打包的镜像：

```bash
./build.sh qemu arm64 virt test
QEMU_MEMORY=256 QEMU_CPUS=1 ./build.sh qemu arm64 virt test
```

Python 测试调用正式启动脚本，等待登录提示、输入 root、等待 shell，执行
架构/系统/BSP 包/DHCP 检查，只有全部成功才输出独占一行的测试标志。
最后执行 `poweroff`，同时要求 QEMU 正常退出。错误或超时时回收子进程。

日志统一位于当前目标的 `logs/`：

| 文件 | 内容 |
| --- | --- |
| `build.log` | 统一入口完整构建日志 |
| `uboot.log` | U-Boot 配置、编译和镜像汇总 |
| `kernel.log` | 内核编译输出 |
| `rootfs-config.log` | Buildroot 配置加载输出 |
| `rootfs.log` | Buildroot 构建输出 |
| `qemu-test.log` | 最近一次实际启动测试的完整串口日志 |

同名日志在下一次操作时会覆盖，需要保留的测试记录应另行备份。

## 11. 增量构建、清理和缓存

```bash
./build.sh qemu arm64 virt clean kernel
./build.sh qemu arm64 virt clean uboot
./build.sh qemu arm64 virt clean rootfs
./build.sh qemu arm64 virt clean all
./build.sh qemu arm64 virt clean rootfs --dry-run
```

组件清理删除当前组件目录及其汇总镜像，并删除需要重新打包的 `boot.scr`。
`clean all` 只删除当前目标输出目录，不删除其他目标或共享下载缓存。

修改源码副本内的文件会影响下次增量构建，但副本会在清理后丢失；正式维护应将
修改保存为 BSP 补丁、板级配置或 DTS。修改 `sources` 或补丁文件后，清理对应组件
再构建，让副本重新准备；更换已导入的 rootfs 工具链后清理 rootfs。

修改 overlay 后重新构建 rootfs 并打包。新增本地包需要补齐 Kconfig、配方及
板级配置。已安装的本地包修改源文件后，可通过 Buildroot 的 `<包名>-rebuild`
目标重新安装，再构建 rootfs 和打包，例如：

```bash
make -C sources/buildroot O="$PWD/output/qemu_arm64_virt/rootfs" \
  DARKOS_BSP_TARGET=qemu_arm64_virt darkos-bsp-info-rebuild
./build.sh qemu arm64 virt rootfs
./build.sh qemu arm64 virt pack
```

## 12. 扩展新板子与排查问题

扩展目标时建立 `boards/<vendor>/<soc>/<board>/bsp.mk`，参考 QEMU 与 RK3588S
现有的分区格式。补齐该目标的内核、U-Boot 和 Buildroot defconfig，按需要加入
各层补丁、DTS、包和 overlay。先执行 `list` 和 `all --dry-run`，再逐组件构建。

目前 QEMU 的打包、启动和实际测试脚本只支持 `qemu arm64 virt`；新增其他
虚拟机或物理板子时需要实现对应镜像组织与启动方法。

| 现象 | 检查位置与处理 |
| --- | --- |
| 编译器过旧或找不到 | 查看打印的工具链前缀和版本，设置正确的组件工具链 |
| 缺少板级 defconfig | 检查 `bsp.mk` 文件路径及 configs 中的实际文件 |
| 补丁失败 | 查看组件日志；确认补丁匹配当前源码，必要时清理副本后重建 |
| 外部工具链检查不通过 | 核对 GCC、headers、libc 和语言能力；不要伪造版本声明 |
| 下载失败 | 检查网络/代理、下载站点和 `BR2_DL_DIR`；保留 hash 校验 |
| 镜像校验失败 | 组件更新后重新执行 `pack` |
| U-Boot 拒绝 initramfs | 核对 raw initrd 支持、加载地址和实际大小 |
| Linux 启动但无登录 | 检查 `ttyAMA0`、`/init`、devtmpfs、BusyBox init 和 getty 配置 |
| 自动测试失败 | 查看 `logs/qemu-test.log`，分辨 U-Boot、内核或用户态阶段 |

QEMU 专用板级操作说明另见 [QEMU ARM64 virt 板级文档](../boards/qemu/arm64/virt/readme.md)。
