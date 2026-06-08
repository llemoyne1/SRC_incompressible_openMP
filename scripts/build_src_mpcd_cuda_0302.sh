#!/usr/bin/env bash
set -euo pipefail

# 0302 — documentation/reproducibility build helper.
# No new core source is introduced at 0302.  This script reuses the 0301/0300
# CUDA source set and only provides a stable binary name for the documented
# nominal backward-step validation.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

OUT=${OUT:-build/src_mpcd_base_cuda_0302}
if [[ -f scripts/build_src_mpcd_cuda_0301.sh ]]; then
  OUT="$OUT" CUDA_ARCH_FLAGS="${CUDA_ARCH_FLAGS:-}" bash scripts/build_src_mpcd_cuda_0301.sh
elif [[ -f scripts/build_src_mpcd_cuda_0300.sh ]]; then
  OUT="$OUT" CUDA_ARCH_FLAGS="${CUDA_ARCH_FLAGS:-}" bash scripts/build_src_mpcd_cuda_0300.sh
else
  OUT="$OUT" CUDA_ARCH_FLAGS="${CUDA_ARCH_FLAGS:-}" bash scripts/build_src_mpcd_cuda_0299.sh
fi

echo "[0302-cuda-build] Built $OUT"
