# QEMU 厂商层

QEMU 在工程中作为虚拟平台，当前机器是 `qemu arm64 virt`。QEMU 提供机器
DTB，构建无需板级 DTS、DDR 初始化固件或 TF-A。内核、U-Boot 和 rootfs
可以分别选择工具链。

配置按以下职责分层：

| 层级 | 文件 | 职责 |
| --- | --- | --- |
| 工程公共层 | `common/bsp.mk` | 共享源码位置、工具链选择策略、默认并发数 |
| QEMU 通用层 | `vendors/qemu/common/bsp.mk` | 加载公共层，选择 QEMU 打包后端 |
| ARM64 架构层 | `vendors/qemu/arm64/bsp.mk` | ARM64 架构、交叉编译前缀、模拟器程序 |
| virt 机器层 | `boards/qemu/arm64/virt/bsp.mk` | 目标标识、组件 defconfig、CPU/内存、启动地址及命令行 |

上层默认使用 `?=`，机器层可以按需覆盖。共享源码版本由 Git 子模块提交
锁定，修改板级配置不会自动下载或切换源码。输出目录由构建入口统一计算，
无需在每块板子重复声明。

内核配置也遵循层级：`arm64/configs/arm64.fragment` 只提供 PSCI 和 SMP；
virt 的 PL011 串口、Virtio 设备及 CPU 数上限位于
`boards/qemu/arm64/virt/configs/kernel.fragment`。其他 QEMU 机器应选择自己的
设备配置；PL011/Virtio 不作为整个 QEMU 厂商层的默认值。

构建入口按工程公共层、QEMU 通用层、架构层、机器层收集补丁和片段。
同一配置项由后层覆盖；常规目标无需重复列出四层路径。
具体构建、配置和运行命令见 [virt 说明](../../boards/qemu/arm64/virt/readme.md)。

查看最终默认值、源码提交和实际合并片段：

```bash
./build.sh qemu arm64 virt config
```

该命令只读，不创建输出目录；`configure` 则会生成并加载 Buildroot 配置。
