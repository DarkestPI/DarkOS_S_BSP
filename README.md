# DarkOS S BSP

工程目录、各脚本步骤、配置层级、下载缓存、产物和维护方法见
[工程说明](doc/README.md)。
当前使用 Git 主仓库和三个源码子模块，拉取、版本锁定和维护方法见
[Git 仓库管理](doc/git-management.md)。多平台扩展时的候选方案见
[repo 管理设计](doc/repo-management.md)。

主仓库拉取后，在工程根目录初始化源码：

```bash
git submodule update --init --recursive --depth 1
git submodule status
```

统一构建入口：

```bash
./build.sh list
./build.sh qemu arm64 virt all
./build.sh qemu arm64 virt test
./build.sh qemu arm64 virt run
./build.sh --help
```

第一个完整仿真目标是 QEMU ARM64 virt，启动 U-Boot、Linux 和最小 BusyBox
rootfs。配置、工具链覆盖、分组件构建、清理以及基于符号链接的
`br2-external` 设计见 [QEMU 板级说明](boards/qemu/arm64/virt/readme.md)。

`boards/<vendor>/<soc>/<board>/bsp.mk` 使用 Makefile 语法。
各目标在 `output/<vendor>_<soc>_<board>/` 中独立构建。
其他板子需要补齐自身的内核、U-Boot 和 Buildroot 配置后才能执行完整构建。
