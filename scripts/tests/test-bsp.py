#!/usr/bin/env python3
"""BSP 入口回归测试：使用临时工程和模拟工具链，不重编正式组件。"""
from pathlib import Path
import hashlib
import json
import os
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
        # 脚本树整体拷入临时工程并固定名为 scripts/，入口为 scripts/build.sh。
        scripts = Path(__file__).resolve().parents[1]
        project = scripts.parent
        shutil.copytree(scripts, self.root / "scripts",
                        ignore=shutil.ignore_patterns("__pycache__"))
        self.board = self.root / "boards/qemu/arm64/test"
        # 2. 创建最小板级文件和公共层，用于验证 Make 变量展开及 external 链接。
        (self.board / "configs").mkdir(parents=True)
        (self.root / "generic/packages").mkdir(parents=True)
        (self.root / "generic/packages/Config.in").write_text("# fixture\n")
        if (project / "generic/bsp.mk").is_file():
            shutil.copy2(project / "generic/bsp.mk", self.root / "generic/bsp.mk")
        (self.board / "configs/rootfs_defconfig").write_text("BR2_aarch64=y\n")
        (self.board / "configs/uboot_defconfig").write_text("CONFIG_ARM=y\n")
        compiler = self.root / "bin/test-gcc"
        # 3. 模拟版本查询，满足 U-Boot 的前置检查，不实际调用交叉编译器。
        compiler.parent.mkdir()
        compiler.write_text("#!/bin/sh\necho 12.3.0\n")
        compiler.chmod(0o755)
        (self.board / "bsp.mk").write_text(
            "-include $(BSP_ROOT)/generic/bsp.mk\n"
            "BSP_ARCH := arm64\n"
            "BSP_CROSS_COMPILE := $(BSP_ROOT)/bin/test-\n"
            "BSP_UBOOT_DEFCONFIG := fixture_defconfig\n"
            "BSP_UBOOT_DEFCONFIG_FILE := $(BOARD_DIR)/configs/uboot_defconfig\n"
            "BSP_BUILDROOT_DEFCONFIG := rootfs_defconfig\n"
            "BSP_BUILDROOT_DEFCONFIG_FILE := $(BOARD_DIR)/configs/rootfs_defconfig\n"
        )
        self.output = self.root / "output/qemu_arm64_test"

    def append_config(self, text):
        with (self.board / "bsp.mk").open("a") as config:
            config.write(text)

    def run_library(self, body):
        return subprocess.run(
            ["bash", "-eo", "pipefail", "-c",
             'source "$1"; bsp_load qemu arm64 test; ' + body,
             "fixture", str(self.root / "scripts/lib/bsp.sh")],
            cwd="/tmp", text=True, stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT)

    def make_layers(self, component="linux"):
        layers = [self.root / "generic", self.root / "vendors/qemu/common",
                  self.root / "vendors/qemu/arm64", self.board]
        fragment_names = (["generic.fragment", "qemu.fragment", "arm64.fragment",
                           "kernel.fragment"] if component == "linux"
                          else ["uboot.fragment"] * 4)
        patches, fragments = [], []
        for layer, name in zip(layers, fragment_names):
            (layer / "patches" / component).mkdir(parents=True, exist_ok=True)
            (layer / "configs").mkdir(parents=True, exist_ok=True)
            # 反向创建，确保收集顺序取决于文件名而非创建时间。
            for filename in ("020-second.patch", "010-first.patch"):
                (layer / "patches" / component / filename).write_text("fixture\n")
            patches.extend(layer / "patches" / component / name
                           for name in ("010-first.patch", "020-second.patch"))
            fragment = layer / "configs" / name
            fragment.write_text("# fixture\n")
            fragments.append(fragment)
        return layers, patches, fragments

    def collected_paths(self, component):
        result = self.run_library(
            f"bsp_collect {component}; "
            'for entry in "${PATCH_FILES[@]}"; do printf "patch=%s\\n" "$entry"; done; '
            'for entry in "${CONFIG_FRAGMENTS[@]}"; do printf "fragment=%s\\n" "$entry"; done')
        self.assertEqual(result.returncode, 0, result.stdout)
        entries = [line.split("=", 1) for line in result.stdout.splitlines()]
        return ([Path(value) for key, value in entries if key == "patch"],
                [Path(value) for key, value in entries if key == "fragment"])

    def test_collection_follows_common_vendor_soc_board_order(self):
        for component in ("linux", "uboot"):
            with self.subTest(component=component):
                _, patches, fragments = self.make_layers(component)
                self.assertEqual(self.collected_paths(component), (patches, fragments))

    def test_explicit_collection_controls_order_and_excludes_other_layers(self):
        for component in ("linux", "uboot"):
            with self.subTest(component=component):
                layers, patches, fragments = self.make_layers(component)
                self.append_config(
                    f"BSP_PATCH_DIRS_{component.upper()} := "
                    f"{layers[3]}/patches/{component} {layers[0]}/patches/{component}\n"
                    f"BSP_FRAGMENTS_{component.upper()} := {fragments[3]} {fragments[1]}\n")
                self.assertEqual(self.collected_paths(component),
                                 (patches[6:8] + patches[0:2],
                                  [fragments[3], fragments[1]]))

    def test_empty_explicit_collection_disables_inherited_files(self):
        for component in ("linux", "uboot"):
            with self.subTest(component=component):
                self.make_layers(component)
                self.append_config(f"BSP_PATCH_DIRS_{component.upper()} :=\n"
                                   f"BSP_FRAGMENTS_{component.upper()} :=\n")
                self.assertEqual(self.collected_paths(component), ([], []))

    def test_config_reports_selected_inputs_and_writes_snapshot(self):
        _, _, fragments = self.make_layers()
        kernel = self.root / "sources/selected-linux"
        uboot = self.root / "sources/selected-u-boot"
        buildroot = self.root / "sources/selected-buildroot"
        firmware = self.root / "firmware/missing-bl31.elf"
        backend = self.root / "scripts/pack-fixture.sh"
        backend.write_text(
            "#!/bin/bash\n"
            "echo 'fixture 镜像: 256 MiB'\n"
            "echo 'boot: 4 MiB 起 / 32 MiB；rootfs: 73728 扇区起'\n")
        self.append_config(
            f"BSP_KERNEL_SOURCE_DIR := {kernel}\n"
            f"BSP_UBOOT_SOURCE_DIR := {uboot}\n"
            f"BSP_BUILDROOT_SOURCE_DIR := {buildroot}\n"
            f"BSP_FRAGMENTS_LINUX := {fragments[3]}\n"
            f"BSP_UBOOT_BL31 := {firmware}\n"
            f"BSP_PACK_SCRIPT := {backend}\n")
        result = self.run_bsp("config")
        self.assertEqual(result.returncode, 0, result.stdout)
        for path in (kernel, uboot, buildroot, fragments[3], firmware):
            self.assertIn(str(path), result.stdout)
        self.assertIn("分区/打包布局:", result.stdout)
        self.assertIn("boot: 4 MiB 起 / 32 MiB；rootfs: 73728 扇区起", result.stdout)
        snapshot = self.output / "bsp.config"
        self.assertTrue(snapshot.is_file(), result.stdout)
        text = snapshot.read_text()
        self.assertIn("# 目标: qemu_arm64_test", text)
        self.assertIn(f"BSP_KERNEL_SOURCE_DIR={kernel}", text)
        self.assertIn(f"BSP_UBOOT_BL31={firmware}", text)
        self.assertIn(f"OUTPUT_DIR={self.output}", text)
        self.assertIn("# 分区/打包布局:", text)
        self.assertIn("# boot: 4 MiB 起 / 32 MiB；rootfs: 73728 扇区起", text)
        # 快照按组件分段，段落之间空一行，变量归入对应段落。
        identity_at = text.index("# 目标与全局\n")
        uboot_at = text.index("\n\n# U-Boot\n")
        kernel_at = text.index("\n\n# 内核\n")
        buildroot_at = text.index("\n\n# Buildroot rootfs\n")
        self.assertLess(identity_at, uboot_at)
        self.assertLess(uboot_at, kernel_at)
        self.assertLess(kernel_at, buildroot_at)
        self.assertIn(f"BSP_UBOOT_BL31={firmware}", text[uboot_at:kernel_at])
        self.assertIn(f"BSP_KERNEL_SOURCE_DIR={kernel}", text[kernel_at:buildroot_at])
        self.assertIn(f"BSP_BUILDROOT_SOURCE_DIR={buildroot}", text[buildroot_at:])

    def test_config_dry_run_skips_snapshot(self):
        result = self.run_bsp("config", "--dry-run")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertFalse(self.output.exists())

    def make_successful_uboot(self, location="sources/u-boot"):
        uboot = self.root / location
        (uboot / "configs").mkdir(parents=True)
        (uboot / "Makefile").write_text(
            ".PHONY: all fixture_defconfig olddefconfig\n"
            "all:\n"
            "\t@printf 'BL31=%s\\nROCKCHIP_TPL=%s\\n' '$(BL31)' '$(ROCKCHIP_TPL)' > build-args.txt\n"
            "\t@printf fixture > u-boot.bin\n"
            "\t@printf fixture > u-boot\n"
            "\t@printf fixture > idbloader.img\n"
            "\t@printf fixture > u-boot.itb\n"
            "\t@printf fixture > u-boot-rockchip.bin\n"
            "fixture_defconfig:\n\t@cp configs/fixture_defconfig .config\n"
            "olddefconfig:\n\t@:\n")
        return uboot

    def test_uboot_selects_source_passes_firmware_and_collects_extra_images(self):
        uboot = self.make_successful_uboot("sources/selected-u-boot")
        firmware = self.root / "firmware"
        firmware.mkdir()
        bl31, tpl = firmware / "bl31.elf", firmware / "ddr.bin"
        bl31.write_bytes(b"fixture-bl31")
        tpl.write_bytes(b"fixture-ddr")
        self.append_config(
            f"BSP_UBOOT_SOURCE_DIR := {uboot}\n"
            f"BSP_UBOOT_BL31 := {bl31}\n"
            f"BSP_UBOOT_TPL := {tpl}\n"
            "BSP_UBOOT_REQUIRE_BL31 := y\n"
            "BSP_UBOOT_REQUIRE_TPL := y\n"
            "BSP_UBOOT_EXTRA_IMAGES := idbloader.img u-boot.itb u-boot-rockchip.bin\n")
        result = self.run_bsp("uboot")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual((self.output / "uboot/build-args.txt").read_text().splitlines(),
                         [f"BL31={bl31}", f"ROCKCHIP_TPL={tpl}"])
        for name in ("u-boot.bin", "u-boot.elf", "idbloader.img", "u-boot.itb",
                     "u-boot-rockchip.bin"):
            self.assertGreater((self.output / "images" / name).stat().st_size, 0)
        self.assertFalse((uboot / ".config").exists())

    def test_required_firmware_fails_before_build_but_dry_run_is_read_only(self):
        self.make_successful_uboot()
        for variable, requirement in (("BSP_UBOOT_BL31", "BSP_UBOOT_REQUIRE_BL31"),
                                      ("BSP_UBOOT_TPL", "BSP_UBOOT_REQUIRE_TPL")):
            with self.subTest(variable=variable):
                firmware = self.root / "firmware" / variable
                self.append_config(f"{variable} := {firmware}\n{requirement} := y\n")
                result = self.run_bsp("uboot", "--dry-run")
                self.assertEqual(result.returncode, 0, result.stdout)
                self.assertIn(str(firmware), result.stdout)
                self.assertFalse(self.output.exists())
                result = self.run_bsp("uboot")
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertIn(str(firmware), result.stdout)
                self.assertFalse((self.output / "uboot").exists())
                self.append_config(f"{requirement} := n\n{variable} :=\n")

    def test_rootfs_uses_selected_buildroot_source(self):
        buildroot = self.root / "sources/selected-buildroot"
        buildroot.mkdir(parents=True)
        (buildroot / "Makefile").write_text(
            ".PHONY: defconfig olddefconfig\n"
            "defconfig:\n\t@echo selected-buildroot-source\n"
            "\t@cp \"$(BR2_DEFCONFIG)\" \"$(O)/.config\"\n"
            "olddefconfig:\n\t@:\n")
        self.append_config(f"BSP_BUILDROOT_SOURCE_DIR := {buildroot}\n"
                           "BSP_ROOTFS_EXTERNAL_AUTO := n\n")
        result = self.run_bsp("configure")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("selected-buildroot-source", result.stdout)
        self.assertIn("BR2_aarch64=y", (self.output / "rootfs/.config").read_text())

    def test_kernel_build_uses_selected_source_and_only_declared_fragments(self):
        kernel = self.root / "sources/selected-linux"
        (kernel / "scripts/kconfig").mkdir(parents=True)
        (kernel / "arch/arm64/configs").mkdir(parents=True)
        minimum = kernel / "scripts/min-tool-version.sh"
        minimum.write_text("#!/bin/sh\necho 10.0.0\n")
        minimum.chmod(0o755)
        merge = kernel / "scripts/kconfig/merge_config.sh"
        merge.write_text("#!/bin/sh\nfor file do\n"
                         '  case "$file" in *.fragment) cat "$file" >> .config ;; esac\n'
                         "done\n")
        merge.chmod(0o755)
        (kernel / "Makefile").write_text(
            ".PHONY: fixture_kernel_defconfig olddefconfig Image\n"
            "fixture_kernel_defconfig:\n"
            "\t@cp arch/arm64/configs/fixture_kernel_defconfig .config\n"
            "olddefconfig:\n\t@:\n"
            "Image:\n\t@mkdir -p arch/arm64/boot\n"
            "\t@printf selected-kernel > arch/arm64/boot/Image\n")
        config = self.board / "configs/kernel_defconfig"
        config.write_text("CONFIG_ARM64=y\n")
        _, _, fragments = self.make_layers()
        fragments[1].write_text("CONFIG_UNSELECTED=y\n")
        fragments[3].write_text("CONFIG_SELECTED=y\n")
        self.append_config(
            f"BSP_KERNEL_SOURCE_DIR := {kernel}\n"
            "BSP_DEFCONFIG := fixture_kernel_defconfig\n"
            f"BSP_DEFCONFIG_FILE := {config}\n"
            "BSP_KERNEL_TARGETS := Image\n"
            "BSP_PATCH_DIRS_LINUX :=\n"
            f"BSP_FRAGMENTS_LINUX := {fragments[3]}\n")
        result = self.run_bsp("kernel")
        self.assertEqual(result.returncode, 0, result.stdout)
        built_config = (self.output / "kernel/.config").read_text()
        self.assertIn("CONFIG_SELECTED=y", built_config)
        self.assertNotIn("CONFIG_UNSELECTED=y", built_config)
        self.assertEqual((self.output / "images/Image").read_text(), "selected-kernel")
        self.assertFalse((kernel / ".config").exists())

    def test_source_paths_resolve_from_project_and_environment_overrides_config(self):
        self.append_config("BSP_KERNEL_SOURCE_DIR := sources/config-linux\n"
                           "BSP_UBOOT_SOURCE_DIR := sources/config-uboot\n"
                           "BSP_BUILDROOT_SOURCE_DIR := sources/config-buildroot\n")
        for component, source, override in (
                ("kernel", "config-linux", "KERNEL_SOURCE_DIR"),
                ("uboot", "config-uboot", "UBOOT_SOURCE_DIR"),
                ("rootfs", "config-buildroot", "BUILDROOT_SOURCE_DIR")):
            with self.subTest(component=component):
                result = self.run_library(f'bsp_source {component}; printf "%s\\n" "$SOURCE_DIR"')
                self.assertEqual(result.returncode, 0, result.stdout)
                self.assertEqual(result.stdout.strip(), str(self.root / "sources" / source))
                result = self.run_library(
                    f'{override}=sources/environment-source; bsp_source {component}; '
                    'printf "%s\\n" "$SOURCE_DIR"')
                self.assertEqual(result.returncode, 0, result.stdout)
                self.assertEqual(result.stdout.strip(),
                                 str(self.root / "sources/environment-source"))

    def test_source_switch_automatically_rebuilds_only_selected_component(self):
        first = self.make_successful_uboot("sources/first-u-boot")
        second = self.make_successful_uboot("sources/second-u-boot")
        (first / "source-marker").write_text("first\n")
        (second / "source-marker").write_text("second\n")
        self.append_config(f"BSP_UBOOT_SOURCE_DIR := {first}\n")
        result = self.run_bsp("uboot")
        self.assertEqual(result.returncode, 0, result.stdout)
        (self.output / "uboot/stale-object.o").write_text("old object")
        (self.output / "kernel").mkdir()
        (self.output / "kernel/keep").write_text("other component")
        self.append_config(f"BSP_UBOOT_SOURCE_DIR := {second}\n")
        result = self.run_bsp("uboot", "--incremental")
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertEqual((self.output / "uboot/source-marker").read_text(), "first\n")
        result = self.run_bsp("uboot")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual((self.output / "uboot/source-marker").read_text(), "second\n")
        self.assertFalse((self.output / "uboot/stale-object.o").exists())
        self.assertTrue((self.output / "kernel/keep").exists())

    def test_source_commit_change_automatically_rebuilds_build_copy(self):
        uboot = self.make_successful_uboot()
        marker = uboot / "source-marker"
        marker.write_text("first\n")

        def git(*args):
            result = subprocess.run(
                ["git", "-C", str(uboot), "-c", "user.name=BSP fixture",
                 "-c", "user.email=bsp-fixture@example.invalid",
                 "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null", *args],
                text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            self.assertEqual(result.returncode, 0, result.stdout)

        git("init", "--quiet")
        git("add", "Makefile", "source-marker")
        git("commit", "--quiet", "-m", "fixture source one")
        result = self.run_bsp("uboot")
        self.assertEqual(result.returncode, 0, result.stdout)
        marker.write_text("second\n")
        git("add", "source-marker")
        git("commit", "--quiet", "-m", "fixture source two")
        result = self.run_bsp("uboot")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual((self.output / "uboot/source-marker").read_text(), "second\n")

    def test_source_edits_sync_incrementally_and_full_drops_stale_objects(self):
        source = self.make_successful_uboot()
        marker = source / "source-marker"
        marker.write_text("first\n")
        result = self.run_bsp("uboot")
        self.assertEqual(result.returncode, 0, result.stdout)
        build = self.output / "uboot"
        stale = build / "retained-object.o"
        stale.write_text("retained")
        config = build / ".config"
        initial_config = config.read_text()
        marker.write_text("second\n")
        result = self.run_bsp("uboot", "--incremental")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual((build / "source-marker").read_text(), "second\n")
        self.assertTrue(stale.exists())
        self.assertEqual(config.read_text(), initial_config)
        result = self.run_bsp("uboot", "--full")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertFalse(stale.exists())

    def test_config_change_rejects_strict_incremental_then_rebuilds(self):
        self.make_successful_uboot()
        result = self.run_bsp("uboot")
        self.assertEqual(result.returncode, 0, result.stdout)
        stale = self.output / "uboot/stale-object.o"
        stale.write_text("old")
        (self.board / "configs/uboot_defconfig").write_text("CONFIG_ARM=y\nCONFIG_NEW=y\n")
        result = self.run_bsp("uboot", "--incremental", "--dry-run")
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertTrue(stale.exists())
        self.assertNotIn("CONFIG_NEW", (self.output / "uboot/.config").read_text())
        result = self.run_bsp("uboot")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertFalse(stale.exists())
        self.assertIn("CONFIG_NEW=y", (self.output / "uboot/.config").read_text())

    def test_patch_change_starts_from_unpatched_source(self):
        source = self.make_successful_uboot()
        (source / "source-marker").write_text("original\n")
        directory = self.board / "patches/uboot"
        directory.mkdir(parents=True)
        patch = directory / "001-marker.patch"
        def write_patch(value):
            patch.write_text("--- a/source-marker\n+++ b/source-marker\n"
                             f"@@ -1 +1 @@\n-original\n+{value}\n")
        write_patch("patched-one")
        result = self.run_bsp("uboot")
        self.assertEqual(result.returncode, 0, result.stdout)
        write_patch("patched-two")
        result = self.run_bsp("uboot")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual((self.output / "uboot/source-marker").read_text(), "patched-two\n")
        patch.unlink()
        result = self.run_bsp("uboot")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertEqual((self.output / "uboot/source-marker").read_text(), "original\n")

    def test_build_options_are_read_only_and_conflicts_fail(self):
        self.make_successful_uboot()
        for options, succeeds in ((["--full", "--dry-run"], True),
                                  (["--dry-run", "--full"], True),
                                  (["--incremental", "--dry-run"], False),
                                  (["--full", "--incremental"], False),
                                  (["--dryrun"], False)):
            with self.subTest(options=options):
                result = self.run_bsp("uboot", *options)
                self.assertEqual(result.returncode == 0, succeeds, result.stdout)
                self.assertFalse(self.output.exists())

    def make_buildable_rootfs(self):
        source = self.make_simple_buildroot("sources/buildroot")
        self.append_config("BSP_ROOTFS_EXTERNAL_AUTO := n\n")
        makefile = source / "Makefile"
        makefile.write_text(".DEFAULT_GOAL := all\n" + makefile.read_text() +
                            "all:\n\t@mkdir -p '$(O)/images' '$(O)/target'\n"
                            "\t@printf fixture > '$(O)/images/rootfs.cpio'\n")
        return source

    def test_rootfs_overlay_updates_incrementally_but_deletions_rebuild(self):
        self.make_buildable_rootfs()
        overlay = self.board / "rootfs-overlay/etc"
        overlay.mkdir(parents=True)
        file = overlay / "fixture"
        file.write_text("first")
        result = self.run_bsp("rootfs")
        self.assertEqual(result.returncode, 0, result.stdout)
        stale = self.output / "rootfs/target/stale-file"
        stale.write_text("old installed file")
        file.write_text("second")
        result = self.run_bsp("rootfs", "--incremental")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertTrue(stale.exists())
        file.unlink()
        result = self.run_bsp("rootfs", "--incremental")
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertTrue(stale.exists())
        result = self.run_bsp("rootfs")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertFalse(stale.exists())

    def test_rootfs_effective_config_change_removes_old_target_files(self):
        self.make_buildable_rootfs()
        result = self.run_bsp("rootfs")
        self.assertEqual(result.returncode, 0, result.stdout)
        stale = self.output / "rootfs/target/removed-package"
        stale.write_text("old package")
        config = self.output / "rootfs/.config"
        config.write_text(config.read_text() + "BR2_PACKAGE_ADDED=y\n")
        result = self.run_bsp("rootfs", "--incremental")
        self.assertNotEqual(result.returncode, 0, result.stdout)
        self.assertTrue(stale.exists())
        result = self.run_bsp("rootfs")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertFalse(stale.exists())
        self.assertIn("BR2_PACKAGE_ADDED=y", config.read_text())

    def test_rootfs_configure_does_not_accept_stale_package_state(self):
        self.make_buildable_rootfs()
        result = self.run_bsp("rootfs")
        self.assertEqual(result.returncode, 0, result.stdout)
        stale = self.output / "rootfs/target/removed-package"
        stale.write_text("old")
        template = self.board / "configs/rootfs_defconfig"
        template.write_text(template.read_text() + "BR2_PACKAGE_ADDED=y\n")
        result = self.run_bsp("configure")
        self.assertEqual(result.returncode, 0, result.stdout)
        result = self.run_bsp("rootfs")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertFalse(stale.exists())

    def test_configure_dry_run_keeps_action_and_creates_no_output(self):
        self.make_buildable_rootfs()
        result = self.run_bsp("configure", "--full", "--dry-run")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertFalse(self.output.exists())

    def test_pack_dispatches_selected_backend(self):
        backend = self.root / "scripts/fixture-pack.sh"
        backend.write_text("#!/bin/sh\nprintf 'selected-pack-backend %s\\n' \"$*\"\n")
        backend.chmod(0o755)
        self.append_config("BSP_PACK_SCRIPT := $(BSP_ROOT)/scripts/fixture-pack.sh\n")
        result = self.run_bsp("pack", "--dry-run")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn("selected-pack-backend qemu arm64 test --dry-run", result.stdout)
        self.assertFalse(self.output.exists())

    def test_all_uses_selected_pack_backend_after_components(self):
        stages = ("cmds/uboot.sh", "cmds/kernel.sh", "cmds/rootfs.sh",
                  "fixture-pack.sh")
        for index, name in enumerate(stages):
            script = self.root / "scripts" / name
            script.write_text(f"#!/bin/sh\necho fixture-stage-{index}\n")
            script.chmod(0o755)
        self.append_config("BSP_PACK_SCRIPT := scripts/fixture-pack.sh\n")
        result = self.run_bsp("all", "--dry-run")
        self.assertEqual(result.returncode, 0, result.stdout)
        observed = [line for line in result.stdout.splitlines()
                    if line.startswith("fixture-stage-")]
        self.assertEqual(observed, [f"fixture-stage-{index}" for index in range(4)])
        self.assertFalse(self.output.exists())

    def run_bsp(self, *args, env=None):
        return self.run_target("qemu", "arm64", "test", *args, env=env)

    def run_target(self, vendor, soc, board, *args, env=None):
        # 从 /tmp 调用临时工程入口，同时检查脚本不依赖当前工作目录。
        return subprocess.run([str(self.root / "scripts" / "build.sh"), vendor, soc, board, *args],
                              cwd="/tmp", text=True, stdout=subprocess.PIPE,
                              stderr=subprocess.STDOUT,
                              env={**os.environ, **(env or {})})

    def test_old_uboot_copy_without_state_automatically_rebuilds(self):
        self.make_successful_uboot()
        build = self.output / "uboot"
        build.mkdir(parents=True)
        (build / "Makefile").write_text("old build copy\n")
        result = self.run_bsp("uboot")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertTrue((build / ".darkos-source").exists())
        self.assertNotEqual((build / "Makefile").read_text(), "old build copy\n")

    def make_simple_buildroot(self, location):
        buildroot = self.root / location
        buildroot.mkdir(parents=True)
        (buildroot / "Makefile").write_text(
            ".PHONY: defconfig olddefconfig\n"
            "defconfig:\n\t@echo selected-buildroot-source\n"
            "\t@cp \"$(BR2_DEFCONFIG)\" \"$(O)/.config\"\n"
            "olddefconfig:\n\t@:\n")
        return buildroot

    def test_rootfs_source_switch_automatically_reconfigures_output(self):
        first = self.make_simple_buildroot("sources/first-buildroot")
        second = self.make_simple_buildroot("sources/second-buildroot")
        self.append_config("BSP_ROOTFS_EXTERNAL_AUTO := n\n"
                           f"BSP_BUILDROOT_SOURCE_DIR := {first}\n")
        result = self.run_bsp("configure")
        self.assertEqual(result.returncode, 0, result.stdout)
        stamp = (self.output / "rootfs/.darkos-source").read_text()
        self.append_config(f"BSP_BUILDROOT_SOURCE_DIR := {second}\n")
        result = self.run_bsp("configure")
        self.assertEqual(result.returncode, 0, result.stdout)
        current = (self.output / "rootfs/.darkos-source").read_text()
        self.assertNotEqual(current, stamp)
        self.assertIn(str(second), current)

    def test_old_rootfs_output_without_state_automatically_reconfigures(self):
        buildroot = self.make_simple_buildroot("sources/buildroot")
        self.append_config("BSP_ROOTFS_EXTERNAL_AUTO := n\n"
                           f"BSP_BUILDROOT_SOURCE_DIR := {buildroot}\n")
        build = self.output / "rootfs"
        build.mkdir(parents=True)
        (build / ".config").write_text("old rootfs config\n")
        result = self.run_bsp("configure")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertTrue((build / ".darkos-source").exists())
        self.assertIn("BR2_aarch64=y", (build / ".config").read_text())

    def test_rootfs_commit_change_automatically_reconfigures_output(self):
        buildroot = self.make_simple_buildroot("sources/buildroot")

        def git(*args):
            result = subprocess.run(
                ["git", "-C", str(buildroot), "-c", "user.name=BSP fixture",
                 "-c", "user.email=bsp-fixture@example.invalid",
                 "-c", "commit.gpgsign=false", "-c", "core.hooksPath=/dev/null", *args],
                text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            self.assertEqual(result.returncode, 0, result.stdout)

        git("init", "--quiet")
        git("add", "Makefile")
        git("commit", "--quiet", "-m", "fixture Buildroot one")
        self.append_config("BSP_ROOTFS_EXTERNAL_AUTO := n\n")
        result = self.run_bsp("configure")
        self.assertEqual(result.returncode, 0, result.stdout)
        stamp = (self.output / "rootfs/.darkos-source").read_text()
        with (buildroot / "Makefile").open("a") as makefile:
            makefile.write("# fixture revision two\n")
        git("add", "Makefile")
        git("commit", "--quiet", "-m", "fixture Buildroot two")
        result = self.run_bsp("configure")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertNotEqual((self.output / "rootfs/.darkos-source").read_text(), stamp)

    def test_default_firmware_hash_mismatch_stops_before_build(self):
        self.make_successful_uboot()
        firmware = self.root / "firmware"
        firmware.mkdir()
        for field in ("BL31", "TPL"):
            with self.subTest(field=field):
                file = firmware / field
                file.write_bytes(f"fixture-{field}".encode())
                variable = f"BSP_UBOOT_{field}"
                checksum = f"{variable}_SHA256"
                self.append_config(f"{variable} := {file}\n{checksum} := {'0' * 64}\n")
                result = self.run_bsp("uboot")
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertIn("固件校验失败", result.stdout)
                self.assertFalse((self.output / "uboot").exists())
                self.append_config(f"{checksum} := {hashlib.sha256(file.read_bytes()).hexdigest()}\n")
                result = self.run_bsp("uboot")
                self.assertEqual(result.returncode, 0, result.stdout)
                result = self.run_bsp("clean", "all")
                self.assertEqual(result.returncode, 0, result.stdout)
                self.append_config(f"{variable} :=\n{checksum} :=\n")

    def test_environment_firmware_override_does_not_use_default_blob_hash(self):
        self.make_successful_uboot()
        firmware = self.root / "firmware"
        firmware.mkdir()
        for field, environment in (("BL31", "BL31"), ("TPL", "ROCKCHIP_TPL")):
            with self.subTest(field=field):
                default = firmware / f"default-{field}"
                override = firmware / f"override-{field}"
                default.write_bytes(b"default-blob")
                override.write_bytes(b"independently-built-blob")
                self.append_config(f"BSP_UBOOT_{field} := {default}\n"
                                   f"BSP_UBOOT_{field}_SHA256 := {'0' * 64}\n")
                result = self.run_bsp("uboot", env={environment: str(override)})
                self.assertEqual(result.returncode, 0, result.stdout)
                self.assertIn(f"{environment}={override}",
                              (self.output / "uboot/build-args.txt").read_text())
                result = self.run_bsp("clean", "all")
                self.assertEqual(result.returncode, 0, result.stdout)
                self.append_config(f"BSP_UBOOT_{field} :=\nBSP_UBOOT_{field}_SHA256 :=\n")

    def make_rockchip_pack_target(self):
        self.rk_board = self.root / "boards/rockchip/rk3588s/test"
        self.rk_board.mkdir(parents=True)
        self.rk_output = self.root / "output/rockchip_rk3588s_test"
        self.rk_images = self.rk_output / "images"
        self.root_uuid = "614e0000-0000-4b53-8000-000000000002"
        (self.rk_board / "bsp.mk").write_text(
            "-include $(BSP_ROOT)/generic/bsp.mk\n"
            "BSP_BOARD_NAME := Rockchip packaging fixture\n"
            "BSP_PACK_SCRIPT := scripts/pack-rockchip.sh\n"
            "BSP_BOOTLOADER_IMAGE := u-boot-rockchip.bin\n"
            "BSP_BOOT_DTB := rk3588s-test.dtb\n"
            "BSP_BOOTLOADER_OFFSET_SECTORS := 64\n"
            "BSP_BOOT_PARTITION_START_MIB := 8\n"
            "BSP_BOOT_PARTITION_SIZE_MIB := 16\n"
            "BSP_IMAGE_SIZE_MIB := 64\n"
            f"BSP_ROOTFS_PARTUUID := {self.root_uuid}\n"
            "BSP_KERNEL_CMDLINE := console=ttyS2,1500000n8 rootwait rw\n")

    def make_rockchip_pack_inputs(self):
        # 这些是打包用占位数据，不是可启动固件，也不代表真机验证。
        self.rk_images.mkdir(parents=True)
        (self.rk_images / "u-boot-rockchip.bin").write_bytes(b"fixture-loader" * 256)
        (self.rk_images / "Image").write_bytes(b"fixture-kernel-image\n")
        (self.rk_images / "rk3588s-test.dtb").write_bytes(b"fixture-board-dtb\n")
        payload = self.root / "rootfs-payload"
        (payload / "etc").mkdir(parents=True)
        (payload / "etc/packaging-fixture").write_text("DarkOS rootfs fixture\n")
        rootfs = self.rk_images / "rootfs.ext4"
        with rootfs.open("wb") as image:
            image.truncate(16 * 1024 * 1024)
        result = subprocess.run(
            ["mkfs.ext4", "-q", "-F", "-d", str(payload), str(rootfs)],
            text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        self.assertEqual(result.returncode, 0, result.stdout)

    def run_rockchip_pack(self, *args):
        return self.run_target("rockchip", "rk3588s", "test", "pack", *args)

    def debugfs_cat(self, image, path):
        result = subprocess.run(["debugfs", "-R", f"cat {path}", str(image)],
                                text=True, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("File not found", result.stderr)
        return result.stdout

    def test_rockchip_pack_dry_run_does_not_create_output(self):
        self.make_rockchip_pack_target()
        result = self.run_rockchip_pack("--dry-run")
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertIn(f"root=PARTUUID={self.root_uuid}", result.stdout)
        self.assertFalse(self.rk_output.exists())

    @unittest.skipUnless(all(shutil.which(tool) for tool in
                            ("sfdisk", "mkfs.ext4", "debugfs", "sha256sum")),
                         "Rockchip image integration requires util-linux and e2fsprogs")
    def test_rockchip_pack_generates_valid_gpt_filesystems_and_boot_config(self):
        self.make_rockchip_pack_target()
        self.make_rockchip_pack_inputs()
        result = self.run_rockchip_pack()
        self.assertEqual(result.returncode, 0, result.stdout)
        sdcard = self.rk_images / "sdcard.img"
        self.assertEqual(sdcard.stat().st_size, 64 * 1024 * 1024)
        result = subprocess.run(["sfdisk", "--json", str(sdcard)], text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        self.assertEqual(result.returncode, 0, result.stderr)
        table = json.loads(result.stdout)["partitiontable"]
        self.assertEqual(table["label"], "gpt")
        boot, rootfs = table["partitions"]
        self.assertEqual((boot["start"], boot["size"]), (8 * 2048, 16 * 2048))
        self.assertEqual((rootfs["start"], rootfs["size"]),
                         (24 * 2048, 64 * 2048 - 24 * 2048 - 34))
        self.assertEqual(rootfs["uuid"].lower(), self.root_uuid)
        for partition in (boot, rootfs):
            self.assertEqual(partition["type"].lower(),
                             "0fc63daf-8483-4772-8e79-3d69d8477de4")
        self.assertEqual([partition["name"] for partition in table["partitions"]],
                         ["boot", "rootfs"])
        saved = json.loads((self.rk_images / "partitions.json").read_text())["partitiontable"]
        self.assertEqual(saved["id"], table["id"])
        self.assertEqual(saved["label"], table["label"])
        for declared, actual in zip(saved["partitions"], table["partitions"]):
            self.assertEqual({key: value for key, value in declared.items() if key != "node"},
                             {key: value for key, value in actual.items() if key != "node"})
        with sdcard.open("rb") as disk:
            for sector, name in ((64, "u-boot-rockchip.bin"),
                                 (boot["start"], "boot.ext4"),
                                 (rootfs["start"], "rootfs.ext4")):
                data = (self.rk_images / name).read_bytes()
                disk.seek(sector * 512)
                self.assertEqual(disk.read(len(data)), data, name)
        config = self.debugfs_cat(self.rk_images / "boot.ext4", "/extlinux/extlinux.conf")
        self.assertEqual(config, (self.rk_images / "extlinux.conf").read_text())
        self.assertIn("LINUX /Image", config)
        self.assertIn("FDT /rk3588s-test.dtb", config)
        self.assertIn(f"root=PARTUUID={self.root_uuid}", config)
        self.assertEqual(self.debugfs_cat(self.rk_images / "boot.ext4", "/Image"),
                         "fixture-kernel-image\n")
        self.assertEqual(self.debugfs_cat(self.rk_images / "boot.ext4", "/rk3588s-test.dtb"),
                         "fixture-board-dtb\n")
        self.assertEqual(self.debugfs_cat(self.rk_images / "rootfs.ext4",
                                        "/etc/packaging-fixture"), "DarkOS rootfs fixture\n")
        result = subprocess.run(["sha256sum", "-c", "SHA256SUMS"], cwd=self.rk_images,
                                text=True, stdout=subprocess.PIPE,
                                stderr=subprocess.STDOUT)
        self.assertEqual(result.returncode, 0, result.stdout)
        self.assertFalse(list(self.rk_output.glob(".pack-rockchip.*")))

    @unittest.skipUnless(all(shutil.which(tool) for tool in ("sfdisk", "mkfs.ext4")),
                         "Rockchip bounds integration requires util-linux and e2fsprogs")
    def test_rockchip_pack_oversized_inputs_preserve_previous_outputs(self):
        self.make_rockchip_pack_target()
        self.make_rockchip_pack_inputs()
        previous = {}
        for name in ("sdcard.img", "boot.ext4", "extlinux.conf", "partitions.json", "SHA256SUMS"):
            previous[name] = f"previous-{name}".encode()
            (self.rk_images / name).write_bytes(previous[name])
        loader = self.rk_images / "u-boot-rockchip.bin"
        rootfs = self.rk_images / "rootfs.ext4"
        for file, size in ((loader, 8 * 1024 * 1024 - 64 * 512 + 1),
                           (rootfs, (64 * 2048 - 24 * 2048 - 34) * 512 + 1)):
            with self.subTest(file=file.name):
                original_size = file.stat().st_size
                with file.open("r+b") as image:
                    image.truncate(size)
                result = self.run_rockchip_pack()
                self.assertNotEqual(result.returncode, 0, result.stdout)
                self.assertIn("超出", result.stdout)
                for name, data in previous.items():
                    self.assertEqual((self.rk_images / name).read_bytes(), data, name)
                self.assertFalse(list(self.rk_output.glob(".pack-rockchip.*")))
                with file.open("r+b") as image:
                    image.truncate(original_size)
        # 原始组件可能使用符号链接，界限必须按链接目标的实际大小检查。
        for file, size in ((loader, 8 * 1024 * 1024 - 64 * 512 + 1),
                           (rootfs, (64 * 2048 - 24 * 2048 - 34) * 512 + 1)):
            with self.subTest(symlink=file.name):
                oversized = self.root / f"oversized-{file.name}"
                with oversized.open("wb") as image:
                    image.truncate(size)
                original = file.with_name(f"original-{file.name}")
                file.rename(original)
                file.symlink_to(oversized)
                try:
                    result = self.run_rockchip_pack()
                    self.assertNotEqual(result.returncode, 0, result.stdout)
                    self.assertIn("超出", result.stdout)
                    for name, data in previous.items():
                        self.assertEqual((self.rk_images / name).read_bytes(), data, name)
                    self.assertFalse(list(self.rk_output.glob(".pack-rockchip.*")))
                finally:
                    file.unlink()
                    original.rename(file)

    def test_config_builds_external_links_and_make_variable_expansion(self):
        # 连续 config 两次，验证 external 可重复生成、相对链接和可选层跳过规则。
        for _ in range(2):
            result = self.run_bsp("config")
            self.assertEqual(result.returncode, 0, result.stdout)
        external = self.output / "br2-external"
        self.assertEqual((external / "layers/generic").resolve(), self.root / "generic")
        self.assertEqual((external / "layers/board").resolve(), self.board)
        self.assertEqual((external / "configs/rootfs_defconfig").resolve(),
                         self.board / "configs/rootfs_defconfig")
        self.assertIn("name: DARKOS", (external / "external.desc").read_text())
        self.assertIn("layers/generic/packages/Config.in", (external / "Config.in").read_text())
        self.assertNotIn("layers/vendor", (external / "Config.in").read_text())

    def test_dry_run_does_not_create_output(self):
        # dry-run 应成功展示操作，并且不创建输出目录。
        result = self.run_bsp("config", "--dry-run")
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
            ".PHONY: defconfig olddefconfig\n"
            "defconfig:\n\t@cp \"$(BR2_DEFCONFIG)\" \"$(O)/.config\"\n"
            "olddefconfig:\n\t@:\n"
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
