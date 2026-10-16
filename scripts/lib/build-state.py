#!/usr/bin/env python3
"""Read-only BSP build planning, source synchronization and successful-build stamps.

Git trees use index object IDs for unchanged files and hash modified/untracked
files. This keeps planning large kernel trees practical without overlooking
working-tree edits. Build output and ignored files never enter source copies.
"""
import argparse
import fnmatch
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import stat
import subprocess
import sys


SCHEMA = 1
STATE = ".darkos-build-state.json"
INCOMPLETE = ".darkos-build-incomplete"
GENERATED = ("*.o", "*.a", "*.ko", "*.mod", "*.cmd", "*.tmp", "*.pyc")
GENERATED_NAMES = {".git", ".config", ".config.old", "__pycache__", "modules.order",
                   "Module.symvers", "u-boot", "u-boot.bin", "u-boot.map",
                   "u-boot.sym", "vmlinux", "System.map"}


def digest_file(path):
    hasher = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            hasher.update(block)
    return hasher.hexdigest()


def file_record(path):
    mode = path.lstat().st_mode
    if stat.S_ISLNK(mode):
        return {"content": "link:" + os.readlink(path), "mode": stat.S_IMODE(mode)}
    if stat.S_ISREG(mode):
        return {"content": "sha256:" + digest_file(path), "mode": stat.S_IMODE(mode)}
    return None


def ignored_source(name):
    # 产物名单只按文件名匹配：路径中间段可能是源码目录（如 include/u-boot），
    # 不能与顶层构建产物 u-boot/vmlinux 等同名即被排除。
    basename = Path(name).parts[-1]
    return (basename in GENERATED_NAMES or basename.startswith(".darkos-")
            or any(fnmatch.fnmatch(basename, pattern) for pattern in GENERATED))


def walk_tree(root, source=False):
    records = {}
    if not root.is_dir():
        return records
    for current, directories, files in os.walk(root, followlinks=False):
        if not source:
            relative_directory = str(Path(current).relative_to(root))
            records[relative_directory + "/"] = {"content": "directory",
                "mode": stat.S_IMODE(Path(current).stat().st_mode)}
        # 目录名不参与产物过滤：只跳过版本库和缓存目录，保留 include/u-boot 等源码目录。
        directories[:] = sorted(d for d in directories if d not in (".git", "__pycache__"))
        # os.walk lists links to directories in directories; record them as links.
        for name in files + [d for d in directories if (Path(current) / d).is_symlink()]:
            path = Path(current) / name
            relative = str(path.relative_to(root))
            if source and ignored_source(relative):
                continue
            record = file_record(path)
            if record is not None:
                records[relative] = record
    return records


def git_output(source, *args):
    environment = dict(os.environ, GIT_OPTIONAL_LOCKS="0")
    return subprocess.check_output(["git", "-C", str(source), *args],
                                   stderr=subprocess.DEVNULL, env=environment)


def source_snapshot(source):
    if not (source / "Makefile").is_file():
        raise ValueError(f"找不到源码 Makefile: {source}")
    if not (source / ".git").exists():
        return "unversioned", walk_tree(source, source=True)
    try:
        revision = git_output(source, "rev-parse", "HEAD").decode().strip()
        entries = git_output(source, "ls-files", "--stage", "-z").split(b"\0")
        modified = set(git_output(source, "ls-files", "--modified", "-z").split(b"\0"))
        untracked = git_output(source, "ls-files", "--others", "--exclude-standard", "-z").split(b"\0")
    except subprocess.CalledProcessError as error:
        raise ValueError(f"无法读取源码 Git 状态: {source}") from error
    records = {}
    for entry in entries:
        if not entry:
            continue
        metadata, raw_name = entry.split(b"\t", 1)
        mode, oid, stage = metadata.split()
        name = os.fsdecode(raw_name)
        if stage != b"0":
            raise ValueError(f"源码存在未解决的 Git 冲突: {name}")
        path = source / name
        if ignored_source(name) or not os.path.lexists(path):
            continue
        if raw_name in modified:
            records[name] = file_record(path)
        else:
            records[name] = {"content": "git:" + oid.decode(),
                             "mode": 0o777 if mode == b"120000" else int(mode, 8) & 0o777}
    for raw_name in untracked:
        if not raw_name:
            continue
        name = os.fsdecode(raw_name)
        if not ignored_source(name):
            records[name] = file_record(source / name)
    return revision, records


def input_snapshot(value):
    if not value:
        return {"path": "", "content": "disabled"}
    path = Path(value).resolve()
    result = {"path": str(path)}
    if not path.is_file():
        result["content"] = "missing"
    else:
        result["content"] = digest_file(path)
    return result


def tree_snapshot(value):
    if not value:
        return {"path": "", "files": {}}
    path = Path(value).resolve()
    return {"path": str(path), "files": walk_tree(path)}


def config_snapshot(value, component):
    path = Path(value).resolve()
    if not path.is_file():
        return {"path": str(path), "content": "missing"}
    values = {}
    for line in path.read_text().splitlines():
        match = re.match(r"(\w+)=(.*)$", line)
        disabled = re.match(r"# (\w+) is not set$", line)
        if match:
            key, setting = match.groups()
        elif disabled:
            key, setting = disabled.group(1), "n"
        else:
            continue
        if component == "rootfs" and key == "BR2_ROOTFS_OVERLAY":
            continue
        values[key] = setting
    return {"path": str(path), "values": values}


def read_state(directory):
    try:
        state = json.loads((directory / STATE).read_text())
        if not isinstance(state, dict) or state.get("schema") != SCHEMA:
            return None
        if not all(isinstance(state.get(key), dict) for key in ("hard", "source_files", "updates")):
            return None
        if not all(isinstance(record, dict) and isinstance(record.get("content"), str) and
                   isinstance(record.get("mode"), int) for record in state["source_files"].values()):
            return None
        if not all(isinstance(tree, dict) and isinstance(tree.get("path"), str) and
                   isinstance(tree.get("files"), dict) for tree in state["updates"].values()):
            return None
        return state
    except (OSError, ValueError, TypeError):
        return None


def plan(args):
    source, directory = Path(args.source).resolve(), Path(args.directory).resolve()
    revision, files = source_snapshot(source)
    hard = {"source-path": str(source), "source-commit": revision}
    hard.update(dict(args.value))
    hard.update({key: input_snapshot(path) for key, path in args.input})
    hard.update({key: tree_snapshot(path) for key, path in args.tree})
    updates = {key: tree_snapshot(path) for key, path in args.update_tree + args.overlay_tree}
    effective = config_snapshot(args.effective_config, args.component) if args.effective_config else None
    previous = read_state(directory)
    full, incremental = [], []
    if (directory / INCOMPLETE).exists():
        full.append("上次构建未完成，需要清理残留结果")
    if previous is None:
        full.append("首次构建或缺少有效的成功构建记录")
    else:
        for key in sorted(set(hard) | set(previous["hard"])):
            if hard.get(key) != previous["hard"].get(key):
                full.append(f"{key} 已变化")
        old_files = previous["source_files"]
        if set(old_files) - set(files):
            full.append("源码文件已删除")
        elif files != old_files:
            if args.component == "rootfs":
                full.append("Buildroot 源码或包构建规则已变化")
            elif args.patched:
                full.append("带 BSP 补丁的源码已变化，需要重新应用补丁")
            else:
                incremental.append("源码工作区已修改，将同步到构建副本")
        for key in sorted(set(updates) | set(previous["updates"])):
            before, after = previous["updates"].get(key), updates.get(key)
            if before == after:
                continue
            if before and (not after or set(before["files"]) - set(after["files"])):
                full.append(f"{key} 文件已删除")
            elif before and after and before["path"] != after["path"]:
                full.append(f"{key} 路径已变化")
            else:
                incremental.append(f"{key} 文件新增或修改")
        if effective is not None and effective != previous.get("effective_config"):
            full.append("有效 .config 已变化或缺失")
    if args.policy == "incremental" and full:
        raise ValueError("无法强制增量编译: " + "；".join(full) + "；请使用 --full 或自动模式")
    mode = "full" if full or args.policy == "full" else "incremental"
    reasons = (["显式指定 --full"] if args.policy == "full" else full) or incremental or ["构建输入未变化，保留已有中间产物"]
    result = {"schema": SCHEMA, "component": args.component, "directory": str(directory),
              "source": str(source), "hard": hard, "source_files": files,
              "updates": updates, "effective_config": effective,
              "effective_config_path": args.effective_config,
              "mode": mode, "reasons": reasons,
              "previous_source_files": previous["source_files"] if previous else {}}
    print(json.dumps(result, ensure_ascii=False, separators=(",", ":")))


def copy_source(data):
    source, directory = Path(data["source"]), Path(data["directory"])
    directory.mkdir(parents=True, exist_ok=True)
    old = data["previous_source_files"] if data["mode"] == "incremental" else {}
    copied = 0
    for name, record in data["source_files"].items():
        target = directory / name
        if old.get(name) == record and os.path.lexists(target):
            continue
        origin = source / name
        target.parent.mkdir(parents=True, exist_ok=True)
        if target.is_symlink():
            target.unlink()
        if origin.is_symlink():
            if target.exists():
                target.unlink()
            target.symlink_to(os.readlink(origin))
        else:
            shutil.copy2(origin, target)
            # Source edits with preserved/older timestamps must still trigger make.
            if data["mode"] == "incremental":
                target.touch()
        copied += 1
    (directory / ".darkos-source").write_text(data["source"] + "\n" + data["hard"]["source-commit"] + "\n")
    print(f"同步源码: {copied} 个文件（{data['mode']}）")


def begin(data):
    directory = Path(data["directory"])
    directory.mkdir(parents=True, exist_ok=True)
    (directory / INCOMPLETE).write_text("Build in progress; only commit clears this marker.\n")


def commit(data):
    directory = Path(data["directory"])
    if data.get("effective_config_path"):
        data["effective_config"] = config_snapshot(data["effective_config_path"], data["component"])
    for key in ("previous_source_files", "mode", "reasons"):
        data.pop(key, None)
    temporary = directory / (STATE + ".tmp")
    temporary.write_text(json.dumps(data, ensure_ascii=False, separators=(",", ":")) + "\n")
    temporary.replace(directory / STATE)
    (directory / INCOMPLETE).unlink(missing_ok=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    subcommands = parser.add_subparsers(dest="action", required=True)
    planner = subcommands.add_parser("plan")
    planner.add_argument("component", choices=("uboot", "kernel", "rootfs"))
    planner.add_argument("source")
    planner.add_argument("directory")
    planner.add_argument("--policy", choices=("auto", "full", "incremental"), default="auto")
    for option in ("value", "input", "tree", "update-tree", "overlay-tree"):
        planner.add_argument("--" + option, nargs=2, action="append", default=[])
    planner.add_argument("--effective-config")
    planner.add_argument("--patched", action="store_true")
    for action in ("begin", "commit", "copy-source", "describe"):
        subcommands.add_parser(action)
    args = parser.parse_args()
    try:
        if args.action == "plan":
            plan(args)
        else:
            data = json.load(sys.stdin)
            if args.action == "describe":
                print(data["mode"])
                print("构建模式: " + ("全量" if data["mode"] == "full" else "增量"))
                for reason in data["reasons"]:
                    print("  原因: " + reason)
            elif args.action == "copy-source":
                copy_source(data)
            elif args.action == "begin":
                begin(data)
            else:
                commit(data)
    except (OSError, ValueError, KeyError) as error:
        print(f"错误: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
