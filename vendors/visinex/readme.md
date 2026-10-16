# 新厂商接入模板

本目录是新厂商（vendor）接入的骨架，不被任何构建脚本读取；复制改名后才生效。
接入步骤：

1. 复制模板：`cp -r vendors/vendor-template vendors/<vendor>`
   （`<vendor>` 只能含字母、数字、下划线和连字符）。
2. 芯片层改名：`mv vendors/<vendor>/soc vendors/<soc>`。
3. 替换占位符：bsp.mk 中全文替换 `<vendor>`、`<soc>`；两个内核片段重命名：
   - `common/configs/vendor.fragment` → `common/configs/<vendor>.fragment`
   - `<soc>/configs/soc.fragment` → `<soc>/configs/<soc>.fragment`
   （构建脚本按厂商名/芯片名查找片段，未改名的片段不会被发现。）
4. 把本 readme 改写为厂商说明，参考 `vendors/qemu/readme.md`。

## 目录职责

| 目录 | 职责 | 必需 |
|---|---|---|
| `common/bsp.mk` | 厂商公共默认值，include 工程公共层 | 是 |
| `common/configs/<vendor>.fragment` | 厂商层内核片段 | 否，文件存在即生效 |
| `common/configs/uboot.fragment` | 厂商层 U-Boot 片段 | 否，同上 |
| `<soc>/bsp.mk` | 芯片层默认值：架构、工具链、固件、芯片基线 | 是 |
| `<soc>/configs/<soc>.fragment` | 芯片层内核片段 | 否，同上 |
| `<soc>/patches/{linux,uboot}/` | 芯片层补丁，按文件名顺序应用 | 否，空目录用 `.gitkeep` 占位 |
| `<soc>/packages/` | Buildroot 包配方，需配 `Config.in` | 否，同上 |
| `rootfs-overlay/`（任意层） | rootfs 覆盖文件 | 按需创建 |

注意：`rootfs-overlay/` 故意不在模板中放 `.gitkeep`——Buildroot 会把该目录完整
rsync 进目标 rootfs，占位文件会变成 rootfs 里的 `/.gitkeep`。需要时创建目录
并放入真实文件即可。

## 板卡侧

厂商层就位后，还需创建 `boards/<vendor>/<soc>/<board>/`：`bsp.mk`（include
芯片层）、`configs/kernel.fragment`、`configs/uboot.fragment`、Buildroot
defconfig 和（真实硬件）`dts/`，参考 `boards/rockchip/rk3588s/lubancat-4/`。

完成后用只读命令核对四层层叠结果：

```bash
./build.sh <vendor> <soc> <board> config
```
