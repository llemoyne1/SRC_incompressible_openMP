#!/usr/bin/env bash
set -euo pipefail

# 0301 — build helper for long backward-step active resampling validation.
# No new core source is introduced at 0301: this reuses the 0300/0299 CUDA
# source set and only changes the default output name.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

OUT=${OUT:-build/src_mpcd_base_cuda_0301}
if [[ -f scripts/build_src_mpcd_cuda_0300.sh ]]; then
  OUT="$OUT" CUDA_ARCH_FLAGS="${CUDA_ARCH_FLAGS:-}" bash scripts/build_src_mpcd_cuda_0300.sh
else
  OUT="$OUT" CUDA_ARCH_FLAGS="${CUDA_ARCH_FLAGS:-}" bash scripts/build_src_mpcd_cuda_0299.sh
fi

echo "[0301-cuda-build] Built $OUT"
