# repo 多仓库管理方案

状态：未来多平台扩展的候选设计，尚未实施 repo 迁移。
当前采用 Git 主仓库和三个源码子模块，实际操作见 [Git 仓库管理](git-management.md)。
以下仓库划分、manifest 和迁移步骤描述采用 repo 时的方案，不是当前工程的管理方式。
目标是统一管理 BSP 工程与上游源码版本，同时保留当前的编译入口、源码副本和
Buildroot 下载缓存机制。

## 1. 设计提出时的情况与需要解决的问题

设计提出时，顶层没有可用的 Git 工作仓库，`manifest.xml` 是空文件。
`sources/linux`、`sources/u-boot`、`sources/buildroot` 已分别具有自己的 Git 历史和远端。
原环境已有 repo launcher，但工程尚未建立 `.repo` 工作区。

已核对的源码基线：

| 项目 | 当前版本标签 | 当前 HEAD |
| --- | --- | --- |
| Linux | `v6.18.55` | `725bd2f3c81d54edccb66fead01d4c0c222e2231` |
| U-Boot | `v2026.10` | `5508406582f6f7120dce0c4b3059819a41788db2` |
| Buildroot | `2026.08` | `d5180309b1b66ef3b8eaccca70ad69be8e0729a1` |

目前 `bsp.mk` 记录了版本和仓库信息，但没有程序据此同步或切换源码。
仅传递这份 BSP 配置，不能保证其他开发者使用相同的三个源码提交；当前
Git 子模块方案已通过主仓库的提交指针锁定三个源码版本。
另外，源码同步后，已有的内核/U-Boot 副本仍可能被复用，造成输入与实际编译内容不一致。

## 2. 推荐仓库划分

新增两个自有仓库，并由 repo 管理四个工作项目：

| 仓库 | 维护内容 |
| --- | --- |
| `darkos-manifests` | manifest、平台 profile、经过验证的版本组合和发布锁定清单 |
| `DarkOS_S_BSP` | 当前工程的 scripts、common、vendors、boards、doc、ci 和入口文件 |
| Linux | 当前上游仓库；需要深度改造时切换到团队维护的 fork |
| U-Boot | 当前上游仓库或团队 fork |
| Buildroot | 当前上游仓库或团队 fork |

manifest 仓库由 `repo init -u` 使用，自身位于 repo 元数据中；其余四个仓库由
`project` 元素同步。manifest 应独立版本管理，通过 `remote`、`project path/revision`
指定源码来源、位置和版本。[repo manifest 官方说明](https://gerrit.googlesource.com/git-repo/+/HEAD/docs/manifest-format.md)

BSP 仓库只提交工程自己的文件，排除：

```gitignore
/sources/
/output/
```

`sources` 中的三个子仓库由 repo 独立管理，不加入 BSP 仓库，也不再配置为
Git submodule。`output` 中的源码副本、external 链接、镜像和下载缓存都不提交。

## 3. 工作区布局

建议在新目录创建 repo 工作区，将当前 BSP 工程整体放在 `bsp/` 项目中：

```text
DarkOS-workspace/
├── .repo/                         # repo 元数据和 manifest checkout
└── bsp/                           # DarkOS_S_BSP Git 项目
    ├── build.sh
    ├── scripts/
    ├── common/
    ├── vendors/
    ├── boards/
    ├── doc/
    ├── ci/
    ├── sources/                   # 父 BSP 项目忽略，repo 单独同步各子项目
    │   ├── linux/                 # 独立 Linux Git 项目
    │   ├── u-boot/                # 独立 U-Boot Git 项目
    │   └── buildroot/             # 独立 Buildroot Git 项目
    └── output/                    # 原有构建输出布局
        ├── downloads/
        └── qemu_arm64_virt/
```

四个 `project` 分别使用 `bsp`、`bsp/sources/linux`、`bsp/sources/u-boot`、
`bsp/sources/buildroot` 路径。子项目目录不由父 BSP Git 跟踪。

开发者在外层执行 repo，在 `bsp/` 中执行构建：

```bash
repo init -u https://YOUR-GIT-SERVER/darkos/darkos-manifests.git \
    -b main -m default.xml
repo sync -j4
cd bsp
./build.sh qemu arm64 virt all
```

这里保留了当前工程内部的路径关系；公共脚本无需为了顶层目录链接重新计算根路径。
当前 BSP 目录可以继续独立构建，迁移验证时无需先移动或清空它。

## 4. manifest 组织

manifest 仓库建议采用：

```text
darkos-manifests/
├── default.xml                    # 初期 include QEMU 的已验证 profile
├── common/
│   ├── remotes.xml                # 公共仓库来源
│   └── bsp.xml                    # BSP 项目
├── profiles/
│   ├── qemu-arm64-virt.xml
│   ├── rockchip-rk3588s-evb1.xml   # 对应平台完整适配后启用
│   └── visinex-<soc>-<board>.xml   # 需要时增加原厂 SDK 组合
└── releases/
    └── <release-name>.xml         # 全部项目固定到提交 SHA
```

profile 决定一个工作区采用哪套源码组合；板级 `bsp.mk` 决定如何配置和编译。
不同平台需要不同原厂内核或 U-Boot 时，在各 profile 中选择不同仓库和 revision，
仍保持相同的 `bsp/sources/*` 路径。

切换 profile 会影响整个工作区的共享原始源码。需要同时开发两套不兼容源码时，
使用两个独立 repo 工作区；通过 `BR2_DL_DIR` 指定共同下载缓存即可。

初期不用拆分 vendor Git 仓库，也不引入 submanifest 或 superproject。
先让 QEMU profile 完成初始化、同步、构建和启动验证；后续按原厂 SDK 的实际
版本和访问权限增加 profile。

### 示例清单

[default.xml.example](repo/default.xml.example) 是单文件设计样例，包含当前核对的
三个源码 SHA。私有 BSP remote 使用保留的 `.invalid` 域名，必须替换为真实地址。
它还不是可直接执行 `repo sync` 的正式清单。

样例中 BSP 跟踪 `main`，适合初期集成；正式发布时必须把 BSP 也锁定到具体 SHA。
`name` 是远端项目名，`path` 是本地工作目录，不能将二者混为一谈。
当前 repo 实现将 remote 的 fetch 前缀与 project name 拼接为 Git URL，
样例中的 `.git` 后缀使三个 URL 与现有源码远端一致。
[URL 拼接实现](https://gerrit.googlesource.com/git-repo/+/refs/heads/main/manifest_xml.py)
如采用 `repo sync -c`，使用正确的 `upstream` ref 指明锁定 SHA 所在的引用。

## 5. 版本与发布规则

建议按以下规则建立版本权威：

1. manifest 的 `revision` 决定实际同步的源码版本。
2. `bsp.mk` 中版本字段保留为期望版本及人类可读说明，不自动 checkout 源码。
3. 构建前检查实际源码版本与选定 profile；不匹配时明确报告。
4. 每个发布清单同时锁定 BSP、Linux、U-Boot、Buildroot 四个项目的 SHA。
5. manifest 仓库的发布 tag 指向对应锁定清单，提供整体工程版本入口。

开发流程允许 BSP 跟踪分支，源码组件优先固定已验证的提交；版本升级通过修改
manifest 提交评审，经过构建及启动测试后再发布。

完成发布验证后，从 repo 工作区导出实际提交清单：

```bash
repo manifest -r -o release-lock.xml
```

将结果纳入 manifest 仓库的 `releases/`，再给该 manifest 提交打发布 tag。
导出时应检查是否包含开发者的 local manifest 覆盖；可发布的清单必须能独立同步。
发布构建要求各项目无未提交源码修改；Git commit SHA 本身不会记录工作区修改。

锁定源码保证源码组合可重现。若要求二进制也可重现，还需固定工具链归档及
sysroot、宿主构建环境、下载包校验值，以及构建时间等输入。
当前工具链自动发现可以保留在开发模式，发布 CI 明确指定各组件工具链前缀。

## 6. 同步源码与构建副本的一致性

保留当前源码副本方案，但建议实施时增加源状态检查。
当前代码尚未实现自动检查，仍需要同步后手动清理相应组件。

未来为每个组件记录状态文件，至少包含：

- 原始源码 Git HEAD。
- 开发模式下的源码工作区差异摘要；发布模式要求干净工作区。
- 各层补丁的文件名、顺序和内容摘要。
- 相关板级文件及实际工具链身份。

首次复制源码后保存状态；后续构建先比较当前输入。
源码 HEAD 或补丁集合变化时停止并要求清理该组件，不继续复用旧副本，
也不自动删除开发者可能尚未保存的副本修改。
源码复制前后复核原始 Git 状态，避免复制期间发生同步而获得混合内容。

| 同步后的变化 | 对已有输出的处理 |
| --- | --- |
| Linux 源码或内核补丁改变 | 清理并重建 kernel，然后 pack |
| U-Boot 源码或补丁改变 | 清理并重建 uboot，然后 pack |
| Buildroot 源码或已导入工具链改变 | 清理并重建 rootfs，然后 pack |
| 板级配置或 overlay 改变 | 按变更内容重配/重建相应组件，并更新输入记录 |
| 文档等非构建输入改变 | 不清理组件 |

同步和构建安排为两个明确步骤，不让 `all` 隐式联网更新源码。
Buildroot 构建直接读取原始源码，工作区内不要同时执行源码同步和构建。
CI 为各 profile 使用独立工作区，避免同时切换共享来源。

## 7. 建议增加的管理入口

以下为待实施功能，不是当前已存在的命令：

| 功能 | 设计行为 |
| --- | --- |
| source status | 展示四个项目的实际 SHA、分支/tag、修改状态和当前 manifest |
| source sync | 检查本地修改与构建占用后调用 repo sync，报告哪些组件需要重建 |
| source lock | 导出四项目固定 SHA 清单，给开发者/CI 做发布输入 |
| build preflight | 检查 profile、板级目标、源码版本和副本状态是否一致 |

直接使用的基础命令仍是 `repo status`、`repo sync`、`repo manifest -r`。
管理脚本不自动执行 `git reset --hard`、清理未提交文件或强制覆盖源码。
用户自己的临时 fork 可以通过 `.repo/local_manifests/` 覆盖项目配置；
正式发布时将必要修改合并到可共享的 profile 中。

## 8. 产物与缓存归档

repo 管理 Git 项目，不管理 Buildroot 的第三方下载包。
`output/downloads` 继续作为下载缓存，并由 Buildroot 的 hash 文件验证内容。
有离线需求时另行准备下载镜像/缓存归档，工具链二进制也放在制品库并记录摘要。

建议发布镜像同时附带：

- 固定 SHA 的 manifest。
- 包含源码状态、板级目标、工具链及构建参数的 `build-info.json`。
- 最终配置、补丁摘要、镜像 `SHA256SUMS` 和启动测试日志。

如果原始源码 dirty 或构建副本被临时修改，产物元信息应明确标记，不能只记录
上游 HEAD 就宣称是对应的纯净发布版本。

## 9. 实施顺序

1. 确认 BSP 与 manifest 的托管地址，准备两个自有 Git 仓库。
2. 从当前工程导出 BSP 文件，排除 `.git`、`sources` 和 `output` 后提交初始版本。
3. 用当前已验证的三个源码 SHA 建立 QEMU manifest，BSP 指向其初始提交或集成分支。
4. 在全新目录执行 repo init/sync，核对四个项目及实际源码 SHA。
5. 在新工作区中执行 QEMU 完整构建及 256 MiB/1 CPU 启动测试。
6. 补齐状态、版本校验、构建副本失效检查和构建输入归档。
7. 导出四项目锁定 manifest，建立第一个发布 tag。
8. 保留旧工作区作迁移对照，再逐步启用 Rockchip、Visinex profile。

验收重点：新机器能从 manifest 得到同一源码组合；源码版本更新不会悄悄复用旧
副本；不同 profile 可以独立开发；源码管理不改变现有构建输出及下载缓存分工。

实施前需要明确的输入只有自有 BSP/manifest 仓库地址、分支约定，以及原厂 SDK
是否需要使用团队私有 fork。本文中的 URL 和目录名称可以据此调整。
