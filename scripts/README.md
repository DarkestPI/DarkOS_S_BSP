# 构建脚本

从工程根目录使用 `./build.sh`。入口根据 `boards/<vendor>/<soc>/<board>/bsp.mk`
选择配置，输出保存在 `output/<vendor>_<soc>_<board>/`，不同板子互不混用。

```bash
./build.sh list
./build.sh rockchip rk3588s lubancat-4 config
./build.sh rockchip rk3588s lubancat-4 uboot
./build.sh rockchip rk3588s lubancat-4 kernel
./build.sh rockchip rk3588s lubancat-4 rootfs
./build.sh rockchip rk3588s lubancat-4 pack
```

`uboot`、`kernel`、`rootfs` 只构建指定组件；组件更新后执行 `pack` 生成启动镜像。
`all` 按 U-Boot → kernel → rootfs → pack 执行，各阶段失败即停止。
`configure` 只加载 Buildroot 配置，`menuconfig` 编辑配置，两者都不编译镜像。

## 增量和全量

默认自动判断，每次构建先打印模式和原因。使用 `--dry-run` 只读检查；可以和
其他选项组合，选项顺序不限。

```bash
./build.sh rockchip rk3588s lubancat-4 kernel --dry-run
./build.sh rockchip rk3588s lubancat-4 kernel --full
./build.sh rockchip rk3588s lubancat-4 rootfs --incremental
./build.sh qemu arm64 virt all --full --dry-run
```

| 输入变化 | 行为 |
| --- | --- |
| 首次构建、旧输出没有构建状态、上次构建中断或失败 | 全量 |
| 源码目录或 Git 提交、工具链、架构变化 | 全量 |
| 内核/U-Boot defconfig、配置片段或补丁变化 | 对应组件全量 |
| 内核/U-Boot 普通源码修改或新增、板级 DTS 修改 | 同步修改后增量；存在补丁时源码修改保守全量 |
| 源码或板级文件删除 | 全量，避免旧源码和产物残留 |
| Buildroot 规则、包配方/本地包源码或有效配置变化 | rootfs 全量，避免复用旧 package stamp 和 target 文件 |
| rootfs overlay 新增或修改 | rootfs 增量 |
| rootfs overlay 删除 | rootfs 全量，清除旧安装文件 |
| 输入未变 | 保留配置和已有中间产物，由 Make 检查依赖 |

`--full` 强制重新准备所选组件。`--incremental` 要求已有兼容状态；若必须全量，
脚本报出原因并返回失败，不自动清理输出。`all` 对三个组件分别判断，因此一次
构建可以同时包含增量和全量阶段。

全量只清理所选组件和它的镜像、失效的打包结果；其他组件和共享下载缓存保留。
只有成功构建并汇总镜像后才保存成功状态。失败或中断的输出在下次构建时全量
重建，以免把部分完成的源码同步或安装当作有效结果。

源码修改维护在 `sources`、BSP 补丁和板级文件中；输出源码副本用于构建，清理或
重建时会丢失其中的手工修改。内核/U-Boot 增量构建保留当前 `.config`；配置模板
变化或全量构建会重新加载板级配置。Buildroot 的菜单修改会在模板未变时保留，
但有效配置变化仍可能触发 rootfs 全量。

构建过程中不要同时更新源码，也不要同时构建同一目标的同一组件。

## 清理和脚本职责

```bash
./build.sh qemu arm64 virt clean kernel --dry-run
./build.sh qemu arm64 virt clean kernel
./build.sh qemu arm64 virt clean all
```

`clean all` 删除当前目标输出目录；共享缓存 `output/downloads` 和其他目标保留。

| 文件 | 职责 |
| --- | --- |
| `build.sh` | 解析命令、选择目标、调度组件和打包后端 |
| `lib/bsp.sh` | 分层配置、源码/工具链选择、补丁、镜像和 external 公共操作 |
| `lib/build-state.py` | 输入指纹、增量兼容性判断和源码同步 |
| `build-uboot.sh` / `build-kernel.sh` / `build-rootfs.sh` | 各组件配置、构建、日志和产物汇总 |
| `prepare-external.sh` | 生成目标专属 br2-external，链接四层 BSP 配置 |
| `pack-qemu.sh` / `pack-rockchip.sh` | 将已有组件产物组合为启动镜像 |
| `run-qemu.sh` / `test-qemu.py` | 启动已有 QEMU 镜像、验证串口和用户态 |
| `tests/test-bsp.py` | 临时工程回归测试，不修改正式输出 |

回归测试：`python3 scripts/tests/test-bsp.py`。
