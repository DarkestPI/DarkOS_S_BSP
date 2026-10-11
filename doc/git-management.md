# Git 主仓库与源码子模块

当前工程使用一个 BSP 主仓库和三个 Git submodule。主仓库维护 scripts、common、
vendors、boards、ci、doc 和构建入口；源码子模块保留各自的 Git 历史。
`output/` 中的源码副本、镜像及下载缓存不提交。

| 子模块 | 初始版本 | 固定提交 |
| --- | --- | --- |
| `sources/linux` | `v6.18.55` | `725bd2f3c81d54edccb66fead01d4c0c222e2231` |
| `sources/u-boot` | `v2026.10` | `5508406582f6f7120dce0c4b3059819a41788db2` |
| `sources/buildroot` | `2026.08` | `d5180309b1b66ef3b8eaccca70ad69be8e0729a1` |

主仓库提交中的 gitlink 决定每个子模块的实际版本，`.gitmodules` 保存仓库地址
和浅克隆设置。`bsp.mk` 中的版本字段用于说明期望版本，不自动切换源码。

## 拉取工程

主仓库发布到 Git 服务后，将它的实际地址赋给 `BSP_REPO_URL`，然后执行：

```bash
git clone --recurse-submodules --shallow-submodules "$BSP_REPO_URL" DarkOS_S_BSP
cd DarkOS_S_BSP
git submodule status
```

如果已拉取主仓库但源码目录为空，或者更新了主仓库中的子模块版本：

```bash
git submodule sync --recursive
git submodule update --init --recursive --depth 1
```

`update` 检出主仓库记录的提交；不使用 `--remote`，避免自动跟随上游分支而
偏离已验证的源码组合。浅克隆保留完整源码，减少提交历史。
如对象库存在额外的未引用数据，可在拉取结束后执行：

```bash
git submodule foreach 'git repack -ad'
```

## 提交 BSP 修改

先用 `git status` 和 `git diff` 检查修改，再选择文件提交，例如：

```bash
git add scripts/build-rootfs.sh
git commit -m "Fix external toolchain configuration"
```

子模块中的文件修改需在子模块自己的仓库中提交，然后由主仓库提交新的 gitlink。
自有源码提交必须推送到其他开发者可访问的 fork，并让 `.gitmodules` 指向该仓库。
仅提交主仓库中的 gitlink，不会把子模块的源码提交上传到上游仓库。
当前 BSP 补丁仍可维护在各层 `patches/` 中。

## 升级源码版本

以 Linux 为例，将目标版本标签赋给 `LINUX_TAG`，再执行：

```bash
git -C sources/linux fetch --depth 1 origin "refs/tags/$LINUX_TAG:refs/tags/$LINUX_TAG"
git -C sources/linux switch --detach "$LINUX_TAG"
```

更新 `bsp.mk` 中相应的版本说明，完成构建和启动验证后，在主仓库提交
`sources/linux` 的新提交指针及相关配置。U-Boot、Buildroot 使用相同流程。

Linux 和 U-Boot 使用输出目录中的源码副本；切换子模块提交后应清理对应组件
再构建，避免复用旧副本。Buildroot 版本或已导入工具链发生变化时清理 rootfs。
不要在同一工作区同时同步源码和构建。

## 发布与后续扩展

BSP 的发布提交同时固定三个源码子模块。发布前确认主仓库和子模块工作区干净，
并确保所有被引用的提交在对应远端可获取。工具链、宿主环境和下载依赖仍需另行
记录，源码提交锁定本身不保证二进制完全相同。

未来同时维护多套厂商 SDK 时，可评估 [repo 管理设计](repo-management.md)。
当前不使用顶层预留的 `manifest.xml` 或 repo 示例同步源码。
