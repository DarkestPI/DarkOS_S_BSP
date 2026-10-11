# QEMU vendor

QEMU is a virtual BSP vendor. The first target is `qemu arm64 virt`.
QEMU supplies the machine DTB; no board DTS, binary firmware, TF-A or physical
device is required. Kernel, U-Boot and rootfs toolchains can be selected separately.

`common/bsp.mk` supplies shared build/machine defaults; `arm64/bsp.mk` supplies
the architecture and emulator settings. Board `bsp.mk` includes those defaults
and selects its own kernel, U-Boot and rootfs configurations.

Shared QEMU kernel configuration lives in `common/configs/qemu.fragment`;
ARM64 configuration lives in `arm64/configs/arm64.fragment`.
