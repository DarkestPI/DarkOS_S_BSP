# 构建脚本（v1 重构）

入口是 `build.sh`：它不做任何具体工作，只定位工程、加载 `lib/`，然后把命令
交给 `cmds/<命令>.sh`。**命令表即 cmds/ 目录**——一命令一文件，看目录就知道
有哪些能力，新增命令只需放入一个文件。

```text
build.sh            入口：定位工程 → 解析参数（lib/entry.sh）→ 分派命令
├── lib/            公共库
│   ├── bsp.sh      分层配置、源码/工具链选择、补丁、镜像、br2-external、快照
│   ├── entry.sh    入口参数解析和命令发现（cmds/ 存在即支持）
│   └── build-state.py  输入指纹、增量兼容性判断和源码同步
├── cmds/           命令实现，接口统一：cmds/<命令>.sh <vendor> <soc> <board> [选项]
│   ├── all.sh      完整流水线：2.1 组件 → 2.2 打包 → 2.3 升级包(预留) → 2.4 报告(预留)
│   ├── uboot.sh / kernel.sh / rootfs.sh   各组件配置、构建、日志和产物汇总
│   ├── configure.sh / menuconfig.sh       rootfs 配置类操作，转发给 rootfs.sh
│   ├── config.sh   显示合并后的配置并生成快照 output/<目标>/bsp.config
│   ├── pack.sh     分派到目标的打包后端（BSP_PACK_SCRIPT）
│   ├── run.sh / test.sh   启动 QEMU / 串口自动化验证
│   ├── clean.sh    清理组件或整个目标输出
│   └── help.sh / list.sh 命令说明 / 目标清单
├── pack-qemu.sh / pack-rockchip.sh   平台打包后端（bsp.mk 按文件名引用）
├── test-qemu.py     QEMU 串口自动化驱动
└── tests/test-bsp.py  临时工程回归测试，不修改正式输出
```

命令脚本收到的是 `<vendor> <soc> <board>` 加用户原始选项；各命令自行校验
自己的选项（`--full/--incremental/--dry-run` 等），入口不做命令相关的判断。

使用方式与旧版一致，只是入口路径不同：

```bash
./scripts-v1/build.sh list
./scripts-v1/build.sh rockchip rk3588s lubancat-4 config
./scripts-v1/build.sh rockchip rk3588s lubancat-4 all --dry-run
```

增量和全量的判定规则、环境变量覆盖见 `doc/README.md`；行为与旧 `scripts/`
入口保持一致。打包后端按 `BSP_PACK_SCRIPT` 配置的文件名优先使用本目录同名
文件，两套脚本目录过渡期间互不混用。稳定后本目录将替换 `scripts/`。

回归测试：`python3 scripts-v1/tests/test-bsp.py`。
