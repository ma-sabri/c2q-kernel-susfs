#!/usr/bin/env bash
set -euo pipefail

# scripts/ci-apply-patches-and-config.sh
# Helper for CI or local runs to apply SuSFS patches and ensure a defconfig exists.
# Usage: ./scripts/ci-apply-patches-and-config.sh [patchfile]

PATCHFILE="${1-}" 

# Ensure expected directories exist
mkdir -p fs include/linux arch/arm64/configs/vendor

# If susfs repo exists under susfs/, copy assets
if [ -d susfs/kernel_patches ]; then
  cp susfs/kernel_patches/fs/* fs/ 2>/dev/null || true
  cp -r susfs/kernel_patches/include/linux/* include/linux/ 2>/dev/null || true
  cp susfs/kernel_patches/KernelSU/10_enable_susfs_for_ksu.patch . 2>/dev/null || true
fi

apply_patch_best_effort() {
  local patchfile="$1"
  if [ ! -f "$patchfile" ]; then
    echo "Patch $patchfile not found"
    return 1
  fi

  # Try git apply first
  if git apply --check "$patchfile" 2>/dev/null; then
    git apply "$patchfile" && return 0
  fi

  # Try patch -p1..-p3
  for p in 1 2 3; do
    if patch -p$p --dry-run < "$patchfile" >/dev/null 2>&1; then
      echo "Applying $patchfile with -p$p"
      patch -p$p < "$patchfile" && return 0
    fi
  done

  # Last resort: git apply --reject
  echo "Applying with git apply --reject (creates .rej files for inspection)"
  git apply --reject --whitespace=fix "$patchfile" || true
  return 2
}

if [ -n "$PATCHFILE" ]; then
  apply_patch_best_effort "$PATCHFILE" || true
else
  if [ -f 10_enable_susfs_for_ksu.patch ]; then
    apply_patch_best_effort 10_enable_susfs_for_ksu.patch || true
  else
    echo "No patch provided and 10_enable_susfs_for_ksu.patch missing; skipping patch apply"
  fi
fi

# Try to ensure kona defconfig exists
if [ ! -f arch/arm64/configs/vendor/kona-perf_defconfig ]; then
  echo "No vendor/kona-perf_defconfig found locally; attempting to fetch from LineageOS as fallback"
  curl -fsSL -o arch/arm64/configs/vendor/kona-perf_defconfig \
    https://raw.githubusercontent.com/LineageOS/android_kernel_oneplus_sm8250/lineage-23.2/arch/arm64/configs/vendor/kona-perf_defconfig || true
fi

# Choose defconfig
if [ -f arch/arm64/configs/vendor/kona-perf_defconfig ]; then
  echo "Using vendor/kona-perf_defconfig"
  make ARCH=arm64 O=out vendor/kona-perf_defconfig
else
  echo "vendor/kona-perf_defconfig not found; searching for alternatives"
  alt=$(ls arch/arm64/configs | grep -i 'kona' | head -n1 || true)
  if [ -n "$alt" ]; then
    echo "Using fallback config: $alt"
    make ARCH=arm64 O=out "$alt"
  else
    echo "No kona config found; falling back to defconfig"
    make ARCH=arm64 O=out defconfig
  fi
fi

# Diagnostic output
git status --porcelain || true
git rev-parse --abbrev-ref HEAD || true
git log -1 --oneline || true
ls -R arch/arm64/configs | sed -n '1,200p'
find . -name '*.rej' -print || true
