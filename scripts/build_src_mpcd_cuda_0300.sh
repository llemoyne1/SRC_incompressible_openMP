#!/usr/bin/env bash
set -euo pipefail

# 0300 — build helper for active CUDA resampling validation.
# No new core source is introduced at 0300: this reuses the 0299 CUDA binary
# source set and only changes the default output name.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

OUT=${OUT:-build/src_mpcd_base_cuda_0300}
OUT="$OUT" CUDA_ARCH_FLAGS="${CUDA_ARCH_FLAGS:-}" bash scripts/build_src_mpcd_cuda_0299.sh

echo "[0300-cuda-build] Built $OUT"
