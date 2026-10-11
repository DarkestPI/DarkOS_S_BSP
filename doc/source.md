在工程根目录执行，目标目录需不存在或为空：

```bash
# Linux
git clone --depth 1 --single-branch --no-tags --branch v6.18.55 \
  https://git.kernel.org/pub/scm/linux/kernel/git/stable/linux-stable.git \
  sources/linux &&
git -C sources/linux repack -ad

# U-Boot
git clone --depth 1 --single-branch --no-tags --branch v2026.10 \
  https://git.u-boot-project.org/u-boot/u-boot.git \
  sources/u-boot &&
git -C sources/u-boot repack -ad

# Buildroot
git clone --depth 1 --single-branch --no-tags --branch 2026.08 \
  https://gitlab.com/buildroot.org/buildroot.git \
  sources/buildroot &&
git -C sources/buildroot repack -ad
```