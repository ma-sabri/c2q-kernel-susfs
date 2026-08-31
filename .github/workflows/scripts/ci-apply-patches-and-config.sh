#!/usr/bin/env bash
set -euo pipefail
# Usage: ./ci-apply-patches-and-config.sh [patch-dir-or-file]
PATCH="$1"
# Ensure expected directories exist
mkdir -p fs include/linux arch/arm64/configs/vendor

# Copy patches assets if they exist
if [ -d susfs/kernel_patches ]; then
  cp susfs/kernel_patches/fs/* fs/ 2>/dev/null || true
  cp -r susfs/kernel_patches/include/linux/* include/linux/ 2>/dev/null || true
  cp susfs/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch . 2>/dev/null || true
fi

# Robust apply
apply_patch_best_effort() {
  patchfile="$1"
  if [ ! -f "$patchfile" ]; then
    echo "Patch $patchfile not found"
    return 1
  fi

  if git apply --check "$patchfile" 2>/dev/null; then
    git apply "$patchfile" && return 0
  fi

  for p in 1 2 3; do
    if patch -p$p --dry-run < "$patchfile" >/dev/null 2>&1; then
      echo "Applying $patchfile with -p$p"
      patch -p$p < "$patchfile" && return 0
    fi
  done

  echo "Applying with git apply --reject (will create .rej files)"
  git apply --reject --whitespace=fix "$patchfile" || true
  return 2
}

if [ -n "$PATCH" ] && [ -f "$PATCH" ]; then
  apply_patch_best_effort "$PATCH" || true
fi

# Try to ensure kona defconfig exists
if [ ! -f arch/arm64/configs/vendor/kona-perf_defconfig ]; then
  echo "No kona-perf_defconfig found locally; attempting to fetch from LineageOS"
  curl -fsSL -o arch/arm64/configs/vendor/kona-perf_defconfig \
    https://raw.githubusercontent.com/LineageOS/android_kernel_oneplus_sm8250/lineage-23.2/arch/arm64/configs/vendor/kona-perf_defconfig || true
fi

# Choose defconfig
if [ -f arch/arm64/configs/vendor/kona-perf_defconfig ]; then
  echo "Using vendor/kona-perf_defconfig"
  make ARCH=arm64 O=out vendor/kona-perf_defconfig
else
  echo "Trying to locate a kona-like config"
  alt=$(ls arch/arm64/configs | grep -i kona | head -n1 || true)
  if [ -n "$alt" ]; then
    echo "Found alternate: $alt"
    make ARCH=arm64 O=out "$alt"
  else
    echo "Falling back to defconfig"
    make ARCH=arm64 O=out defconfig
  fi
fi

# Dump diagnostics
git status --porcelain
git rev-parse --abbrev-ref HEAD || true
git log -1 --oneline || true
ls -R arch/arm64/configs | sed -n '1,200p'
find . -name '*.rej' -print || true
