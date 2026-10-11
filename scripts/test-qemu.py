#!/usr/bin/env python3
"""启动实际 QEMU 镜像，通过串口登录、验证用户态并正常关机。"""
import os
from pathlib import Path
import re
import selectors
import subprocess
import sys
import time


def main():
    # 1. 限定已实现的 QEMU 目标，建立日志目录及整个测试的超时期限。
    target = sys.argv[1:] or ["qemu", "arm64", "virt"]
    if target != ["qemu", "arm64", "virt"]:
        raise SystemExit("Only qemu arm64 virt is supported")
    root = Path(__file__).resolve().parent.parent
    logs = root / "output/qemu_arm64_virt/logs"
    logs.mkdir(parents=True, exist_ok=True)
    deadline = time.monotonic() + int(os.environ.get("QEMU_TEST_TIMEOUT", "120"))
    command = [str(root / "scripts/run-qemu.sh"), *target]
    # 2. 复用正式启动脚本，以管道接收串口并向 guest 输入登录和测试命令。
    process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
                               stderr=subprocess.STDOUT)
    selector = selectors.DefaultSelector()
    # selectors 避免阻塞读取串口，启动没有输出时也能检查超时。
    selector.register(process.stdout, selectors.EVENT_READ)
    output = bytearray()
    state = "boot"
    passed = False
    try:
        with (logs / "qemu-test.log").open("wb") as log:
            # 3. 串口输出同时写入终端、日志和最近输出缓冲，按状态识别提示符。
            while time.monotonic() < deadline:
                for key, _ in selector.select(timeout=1):
                    data = os.read(key.fileobj.fileno(), 65536)
                    if not data:
                        selector.unregister(key.fileobj)
                        continue
                    log.write(data)
                    log.flush()
                    sys.stdout.buffer.write(data)
                    sys.stdout.buffer.flush()
                    output.extend(data)
                    recent = bytes(output[-65536:])
                    if any(error in recent for error in (
                        b"Kernel panic", b"Wrong Ramdisk Image Format",
                        b"Ramdisk image is corrupt", b"Bad Linux ARM64 Image magic",
                    )):
                        # 已知启动错误立即报告，无需等待完整的超时期限。
                        raise RuntimeError("Boot failed; see qemu-test.log")
                    if state == "boot" and b"darkos-qemu login:" in recent:
                        # 4. 出现登录提示后输入 root；当前开发 rootfs 使用空密码。
                        process.stdin.write(b"root\n")
                        process.stdin.flush()
                        state = "login"
                    elif state == "login" and re.search(rb"(?:\r?\n|\r)[^\r\n]*# $", recent):
                        # 5. 进入 root shell 后检查架构、proc、BSP 包及 DHCP 地址。
                        # 只有全部检查成功才输出标志；无论检查结果如何都关机。
                        process.stdin.write(
                            b"uname -a; darkos-info; ip addr show dev eth0; "
                            b"test \"$(uname -m)\" = aarch64 && "
                            b"test -r /proc/1/status && "
                            b"grep -q 'Target: qemu_arm64_virt' /etc/darkos-bsp-release && "
                            b"ip -4 addr show dev eth0 | grep -q 'inet ' && "
                            b"printf '\\nDARKOS_QEMU_TEST_OK\\n'; poweroff\n"
                        )
                        process.stdin.flush()
                        state = "check"
                    if re.search(rb"(?:^|\n)DARKOS_QEMU_TEST_OK\r?\n", recent):
                        # 标志必须独占一行，避免把串口回显的命令文本当作成功。
                        passed = True
                if process.poll() is not None and not selector.get_map():
                    break
            else:
                raise RuntimeError("QEMU boot/login/shutdown timed out")
        # 6. 同时要求 guest 检查成功和 QEMU 正常退出，才能判定测试通过。
        if not passed or process.returncode != 0:
            raise RuntimeError(f"QEMU validation failed (exit={process.returncode}, state={state})")
        print("PASS: U-Boot → Linux → BusyBox; root login, AArch64, DHCP, linked package, poweroff")
        print(f"Serial log: {logs / 'qemu-test.log'}")
    finally:
        # 7. 无论成功、失败或异常，都关闭句柄并回收仍在运行的 QEMU 子进程。
        selector.close()
        if process.poll() is None:
            process.terminate()
            try:
                process.wait(timeout=5)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
        process.stdin.close()
        process.stdout.close()


if __name__ == "__main__":
    # 统一将测试失败转换为退出码 1，供总入口或 CI 判断。
    try:
        main()
    except RuntimeError as error:
        print(f"FAIL: {error}", file=sys.stderr)
        raise SystemExit(1)
