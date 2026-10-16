# OP-TEE 可选源码与用户态服务

本工程为 ARM64 目标接入 [OP-TEE](https://optee.readthedocs.io/en/latest/architecture/index.html)
作为可选安全模块。`sources/optee_os` 是在安全世界运行的 Trusted OS 源码；
`sources/optee_client` 提供普通世界的 `libteec` 和 `tee-supplicant`。
后者负责 OP-TEE 请求的文件访问等 RPC 服务，不能单独创建可信执行环境。
组件关系见 [Linux OP-TEE 驱动文档](https://docs.kernel.org/tee/op-tee.html)。

## 源码版本与构建范围

OS 固定使用 **4.9.0**（上游最新正式版为 4.10.0，基线有意滞后）；client 固定使用
**4.10.0**，与上游最新正式版一致。Buildroot 2026.08 原生包默认 client 版本为
4.9.0，本工程通过 `OPTEE_CLIENT_OVERRIDE_SRCDIR` 以本地源码构建 4.10.0。
子模块提交分别为：

| 目录 | 提交 | 上游 |
| --- | --- | --- |
| `sources/optee_os` | `c2b0684fcd89929976a8726e6e3af922b48dd2c7` | [OP-TEE OS 4.9.0](https://github.com/OP-TEE/optee_os/releases/tag/4.9.0) |
| `sources/optee_client` | `9f5e90918093c1d1cd264d8149081b64ab7ba672` | [OP-TEE client 4.10.0](https://github.com/OP-TEE/optee_client/releases/tag/4.10.0) |

```bash
git submodule update --init --depth 1 -- sources/optee_os sources/optee_client
git submodule status -- sources/optee_os sources/optee_client
```

现有脚本仅编译 client，采用 Buildroot 原生 `optee-client` 包，并通过
`OPTEE_CLIENT_OVERRIDE_SRCDIR` 使用本地源码；配置和编译产物仍按目标保存在
`output/<vendor>_<soc>_<board>/rootfs/`。`optee_os` 暂作 BL32 后续适配的源码，
不会由 `all` 自动编译、打包或加载。

## 可选启用

默认 `BSP_OPTEE_CLIENT_ENABLE=n`。可在适配好的板级 `bsp.mk` 设置为 `y`，
或使用环境变量临时启用：

```bash
BSP_OPTEE_CLIENT_ENABLE=y ./build.sh qemu arm64 virt rootfs --dry-run
BSP_OPTEE_CLIENT_ENABLE=y ./build.sh qemu arm64 virt rootfs
```

这两条命令准备用户态支持；当前 QEMU 的原有启动链仍需按下一节适配后，
才能实际运行 OP-TEE。如需使用另一份 client 源码，可设置
`OPTEE_CLIENT_SOURCE_DIR=/absolute/path/to/optee_client`；板级默认路径由
`BSP_OPTEE_CLIENT_SOURCE_DIR` 控制。`BSP_OPTEE_OS_SOURCE_DIR` 记录 OS 源码位置。
更换源码路径、提交或启用状态时，rootfs 构建模式会重新判断是否需要全量构建。

启用后，BusyBox/SysV init 使用 `S30tee-supplicant`。没有 `/dev/teepriv0` 时，
服务输出跳过原因并正常返回；设备存在而守护程序缺失时报告失败。
`BR2_PACKAGE_DARKOS_OPTEE_CLIENT_SERVICE` 可在 `./build.sh <vendor> <soc> <board> menuconfig` 中关闭，
恢复原生 Buildroot 启动脚本。这个开关不影响 client 是否编入 rootfs。
脚本自动启用 client 时关闭 RPMB 模拟；调试时可由 Buildroot 配置单独开启。

## 安全世界运行所需的配套

当前 QEMU 使用 `-machine virt` 和 `-bios u-boot.bin`；QEMU 的 TrustZone 仿真
默认关闭。完整适配需要 `secure=on`、安全监控固件 TF-A、OP-TEE BL32、
作为 BL33 的 U-Boot，以及一致的安全内存、共享内存和 DT 描述。
参考 [QEMU virt 参数](https://qemu.readthedocs.io/en/master/system/arm/virt.html)
和 [OP-TEE 官方 QEMU v8 构建配方](https://github.com/OP-TEE/build/blob/4.9.0/qemu_v8.mk)。
该配方展示 `SPD=opteed`、`BL32`、`BL32_EXTRA1`、`BL32_EXTRA2` 的连接关系；
现有 BSP 尚未完成这条安全启动链的验证。

OP-TEE 4.9.0 的 [Rockchip 平台配置](https://github.com/OP-TEE/optee_os/blob/4.9.0/core/arch/arm/plat-rockchip/conf.mk)
已有 `rk3588` flavor，但 LubanCat-4/RK3588S 仍需要按实板适配与验证：

- 确认所选 BL31 支持对应 OP-TEE SMC ABI，以及 BL32 的装载地址和交接。
- 将 BL32 纳入 U-Boot FIT/板级启动镜像；本工程当前只配置 DDR/TPL 与 BL31。
- 配置安全内存隔离、保留区和共享内存，保证各启动阶段与内核 DT 一致。
- 内核启用 `CONFIG_TEE=y`、`CONFIG_OPTEE=y`，并提供有效的 OP-TEE DT 节点。
- 检查启动日志、`/dev/tee0`、`/dev/teepriv0` 和 `tee-supplicant`，再用
  OP-TEE `xtest` 验证 Trusted Application 调用与存储。

源码接入和 daemon 安装均不表示完成硬件可信启动，也不表示建立了设备根信任。
OP-TEE 的 RK3588 配置包含 OTP/secure-boot 功能，当前保留其默认模拟行为；
本工程脚本不执行 OTP 熔丝操作。平台迁移与密钥/内存要求见
[OP-TEE porting guidelines](https://optee.readthedocs.io/en/latest/architecture/porting_guidelines.html)。
