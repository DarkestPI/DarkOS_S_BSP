# 新板卡接入模板

本目录是新板卡（board）接入的骨架，不被任何构建脚本读取；复制改名后才生效。
前置条件：`vendors/<vendor>/<soc>/` 已存在（新厂商先用 `vendors/vendor-template`）。

1. 复制模板到芯片层下（父目录可能尚不存在，先创建）：
   `mkdir -p boards/<vendor>/<soc> && cp -r boards/board-template boards/<vendor>/<soc>/<board>`
   （`<board>` 只能含字母、数字、下划线和连字符。）
2. 全文替换 bsp.mk、configs/ 下各文件中的 `<vendor>/<soc>/<board>` 占位符。
3. 重命名两个 defconfig：
   `configs/board_defconfig` → `configs/<board>_defconfig`（内核）
   `configs/darkos_board_defconfig` → `configs/darkos_<board>_defconfig`（Buildroot）
4. 按板卡实际情况修改：
   - `dts/` 放入本板设备树（`.dts`/`.dtsi`），与 bsp.mk 的 `BSP_DTS_NAME` 一致；
   - `configs/<board>_defconfig` 保持极简基座即可，硬件差异写在片段里；
   - `configs/kernel.fragment` 补本板设备树对应的供电/PHY/RTC 等驱动选项；
   - `configs/darkos_<board>_defconfig` 按调试串口和 CPU 核型号调整；
   - 虚拟目标（QEMU 类）删去 DTS 相关行，参考 `boards/qemu/arm64/virt/`。
5. 把本 readme 改写为板卡说明，参考资料放 `doc/`，参考
   `boards/rockchip/rk3588s/lubancat-4/`。

## 目录职责

| 目录/文件 | 职责 | 必需 |
|---|---|---|
| `bsp.mk` | 板级配置，include 芯片层，`:=` 覆盖上层默认值 | 是 |
| `configs/kernel.fragment` | 板级内核片段（四层片段链的最后一环） | 否，文件在即生效 |
| `configs/uboot.fragment` | 板级 U-Boot 片段 | 否，同上 |
| `configs/<board>_defconfig` | 板级内核 defconfig | 否，缺省用芯片层 |
| `configs/darkos_<board>_defconfig` | 板级 Buildroot defconfig | 是 |
| `dts/` | 板级设备树，构建时复制进内核/U-Boot 源码树 | 真实硬件必需 |
| `patches/{linux,uboot}/` | 板级补丁，按文件名顺序应用 | 否，空目录用 `.gitkeep` |
| `doc/` | 板卡参考资料 | 否 |
| `rootfs-overlay/` | 板级 rootfs 覆盖文件 | 按需创建 |

注意：`rootfs-overlay/` 故意不放 `.gitkeep`——Buildroot 会把该目录完整 rsync
进目标 rootfs，占位文件会变成 rootfs 里的 `/.gitkeep`。需要时创建目录并放入
真实文件即可。

完成后用只读命令核对四层层叠结果，确认目标出现在列表中：

```bash
./build.sh list
./build.sh <vendor> <soc> <board> config
```
