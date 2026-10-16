#!/bin/bash
# 命令说明；每个命令的实现都在 cmds/<命令>.sh，可对照阅读。
cat <<'HELP'
用法: ./build.sh <vendor> <soc> <board> [命令] [选项]
      ./build.sh list | help
命令（实现见 cmds/ 目录，一命令一文件）:
  all          完整流水线：U-Boot → 内核 → rootfs → 打包（默认）
  uboot        仅编译 U-Boot
  kernel       仅编译内核
  rootfs       仅编译 Buildroot rootfs
  configure    生成 br2-external 并加载 Buildroot 配置，不编译
  menuconfig   打开 Buildroot 配置菜单
  config       生成 br2-external，显示继承后的 BSP 配置并生成快照
               output/<目标>/bsp.config
  pack         调用当前平台的打包后端生成启动镜像及校验文件
  run          启动 QEMU（root 登录，空密码；Ctrl+A X 退出）
  test         启动 QEMU，验证登录、架构、网络接口并关机
  clean [uboot|kernel|rootfs|all]   清理所选目标或组件
构建选项（all/uboot/kernel/rootfs/configure/menuconfig）:
  --full         强制所选组件全量重建，保留其他组件和下载缓存
  --incremental  仅允许兼容的增量构建；需要全量时报告原因并退出
  --dry-run      只读显示操作及全量/增量判定，不编译或清理
默认自动判断：首次构建或不兼容输入变化时全量，其余复用构建结果。
环境变量: JOBS、KERNEL_CROSS_COMPILE、UBOOT_CROSS_COMPILE、ROOTFS_CROSS_COMPILE
          KERNEL_SOURCE_DIR、UBOOT_SOURCE_DIR、BUILDROOT_SOURCE_DIR、BL31、ROCKCHIP_TPL
示例: ./build.sh qemu arm64 virt all
      ./build.sh rockchip rk3588s lubancat-4 kernel --full
HELP
