#!/usr/bin/env python3
"""BSP 入口回归测试：使用临时工程和模拟工具链，不重编正式组件。"""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class BspScriptsTest(unittest.TestCase):
    def setUp(self):
        # 1. 每项测试创建独立临时工程；结束后自动删除，避免触碰正式 output。
        self.temp = tempfile.TemporaryDirectory(prefix="darkos-bsp-test-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        source = Path(__file__).resolve().parents[2]
        shutil.copytree(source / "scripts", self.root / "scripts")
        shutil.copy2(source / "build.sh", self.root / "build.sh")
        self.board = self.root / "boards/qemu/arm64/test"
        # 2. 创建最小板级文件和公共层，用于验证 Make 变量展开及 external 链接。
        (self.board / "configs").mkdir(parents=True)
        (self.root / "common/packages").mkdir(parents=True)
        (self.root / "common/packages/Config.in").write_text("# fixture\n")
        (self.board / "configs/rootfs_defconfig").write_text("BR2_aarch64=y\n")
        (self.board / "configs/uboot_defconfig").write_text("CONFIG_ARM=y\n")
        compiler = self.root / "bin/test-gcc"
        # 3. 模拟版本查询，满足 U-Boot 的前置检查，不实际调用交叉编译器。
        compiler.parent.mkdir()
        compiler.write_text("#!/bin/sh\necho 12.3.0\n")
        compiler.chmod(0o755)
        (self.board / "bsp.mk").write_text(
            "BSP_ARCH := arm64\n"
            "BSP_CROSS_COMPILE := $(BSP_ROOT)/bin/test-\n"
            "BSP_UBOOT_DEFCONFIG := fixture_defconfig\n"
            "BSP_UBOOT_DEFCONFIG_FILE := $(BOARD_DIR)/configs/uboot_defconfig\n"
            "BSP_BUILDROOT_DEFCONFIG := rootfs_defconfig\n"
            "BSP_BUILDROOT_DEFCONFIG_FILE := $(BOARD_DIR)/configs/rootfs_defconfig\n"
        )
        self.output = self.root / "output/qemu_arm64_test"

    def run_bsp(self, *args):
        # 从 /tmp 调用临时工程入口，同时检查脚本不依赖当前工作目录。
        return subprocess.run([str(self.root / "build.sh"), "qemu", "arm64", "test", *args],
                              cwd="/tmp", text=True, stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT)

    def test_prepare_links_and_make_variable_expansion(self):
        # 连续 prepare 两次，验证可重复生成、相对链接和可选层跳过规则。
        for _ in range(2):
            result = self.run_bsp("prepare")
            self.assertEqual(result.returncode, 0, result.stdout)
        external = self.output / "br2-external"
        self.assertEqual((external / "layers/common").resolve(), self.root / "common")
        self.assertEqual((external / "layers/board").resolve(), self.board)
        self.assertEqual((external / "configs/rootfs_defconfig").resolve(),
                         self.board / "configs/rootfs_defconfig")
        self.assertIn("name: DARKOS", (external / "external.desc").read_text())
        self.assertIn("layers/common/packages/Config.in", (external / "Config.in").read_text())
        self.assertNotIn("layers/vendor", (external / "Config.in").read_text())

    def test_dry_run_does_not_create_output(self):
        # dry-run 应成功展示操作，并且不创建输出目录。
        result = self.run_bsp("prepare", "--dry-run")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertFalse(self.output.exists())

    def test_clean_kernel_preserves_other_components(self):
        # 使用占位文件确认 clean kernel 只删除对应组件及镜像。
        for name in ("kernel", "uboot", "rootfs", "images"):
            (self.output / name).mkdir(parents=True)
        for name in ("Image", "u-boot.bin", "rootfs.cpio.gz"):
            (self.output / "images" / name).write_text("fixture")
        result = self.run_bsp("clean", "kernel")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertFalse((self.output / "kernel").exists())
        self.assertFalse((self.output / "images/Image").exists())
        for name in ("uboot", "rootfs", "images/u-boot.bin", "images/rootfs.cpio.gz"):
            self.assertTrue((self.output / name).exists(), name)

    def test_unknown_clean_option_preserves_output(self):
        # 拼错 --dry-run 必须报错，而不是悄悄执行清理。
        (self.output / "kernel").mkdir(parents=True)
        result = self.run_bsp("clean", "kernel", "--dryrun")
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertTrue((self.output / "kernel").exists())

    def test_rootfs_rpc_overrides_template_and_tracks_toolchain(self):
        # 工具链能力必须覆盖模板；切换能力后 configure 应重新加载配置。
        buildroot = self.root / "sources/buildroot"
        options = buildroot / "toolchain/toolchain-external/toolchain-external-custom/Config.in.options"
        options.parent.mkdir(parents=True)
        options.write_text("config BR2_TOOLCHAIN_EXTERNAL_HEADERS_6_1\n")
        (buildroot / "Makefile").write_text(
            ".PHONY: defconfig\n"
            "defconfig:\n\t@cp \"$(BR2_DEFCONFIG)\" \"$(O)/.config\"\n"
        )
        sysroot = self.root / "toolchain/sysroot"
        rpc_header = sysroot / "usr/include/rpc/rpc.h"
        rpc_header.parent.mkdir(parents=True)
        libc = sysroot / "usr/lib/libc.a"
        libc.parent.mkdir(parents=True)
        libc.touch()
        (self.root / "bin/test-gcc").write_text(
            "#!/usr/bin/env python3\n"
            "import sys\n"
            "if '-dumpfullversion' in sys.argv:\n"
            "    print('13.4.0')\n"
            "elif '-print-file-name=libc.a' in sys.argv:\n"
            f"    print({str(libc)!r})\n"
            "elif '-E' in sys.argv:\n"
            "    source = sys.stdin.read()\n"
            "    print('#define LINUX_VERSION_CODE 393472' if 'linux/version.h' in source\n"
            "          else '#define __GLIBC__ 2')\n"
            "else:\n"
            "    sys.exit(1)\n"
        )
        with (self.board / "bsp.mk").open("a") as config:
            config.write("BSP_ROOTFS_EXTERNAL_AUTO := y\n")
        for has_rpc in (False, True, False):
            with self.subTest(has_rpc=has_rpc):
                if has_rpc:
                    rpc_header.touch()
                elif rpc_header.exists():
                    rpc_header.unlink()
                template_rpc = ("# BR2_TOOLCHAIN_EXTERNAL_INET_RPC is not set" if has_rpc
                                else "BR2_TOOLCHAIN_EXTERNAL_INET_RPC=y")
                (self.board / "configs/rootfs_defconfig").write_text(
                    f"BR2_aarch64=y\n{template_rpc}\n")
                result = self.run_bsp("configure")
                self.assertEqual(result.returncode, 0, result.stdout)
                expected = ("BR2_TOOLCHAIN_EXTERNAL_INET_RPC=y" if has_rpc
                            else "# BR2_TOOLCHAIN_EXTERNAL_INET_RPC is not set")
                for name in ("rootfs.defconfig", "rootfs/.config", "rootfs/.darkos-defconfig"):
                    lines = (self.output / name).read_text().splitlines()
                    self.assertEqual([line for line in lines if "BR2_TOOLCHAIN_EXTERNAL_INET_RPC" in line],
                                     [expected])

    def make_failing_uboot(self):
        # 构造配置成功、编译失败的 Makefile，专门测试失败传播。
        uboot = self.root / "sources/u-boot"
        (uboot / "configs").mkdir(parents=True)
        (uboot / "Makefile").write_text(
            ".PHONY: all fixture_defconfig\n"
            "all:\n\t@echo simulated-compile-error\n\t@exit 2\n"
            "fixture_defconfig:\n\t@cp configs/fixture_defconfig .config\n"
        )

    def test_build_failure_is_not_hidden_by_tee(self):
        # 单组件失败须返回非零、保留错误日志且不复制成功产物。
        self.make_failing_uboot()
        result = self.run_bsp("uboot")
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("simulated-compile-error", result.stdout)
        self.assertFalse((self.output / "images/u-boot.bin").exists())
        self.assertIn("simulated-compile-error", (self.output / "logs/uboot.log").read_text())

    def test_all_stops_after_component_failure(self):
        # 总入口记录失败后应停止，不能继续进入内核/rootfs 阶段。
        self.make_failing_uboot()
        result = self.run_bsp("all")
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertIn("simulated-compile-error", result.stdout)
        self.assertNotIn("找不到内核源码", result.stdout)
        self.assertNotIn("Buildroot:", result.stdout)
        self.assertIn("simulated-compile-error", (self.output / "logs/build.log").read_text())


if __name__ == "__main__":
    # unittest 收集并执行测试，测试失败会返回非零退出码。
    unittest.main()
