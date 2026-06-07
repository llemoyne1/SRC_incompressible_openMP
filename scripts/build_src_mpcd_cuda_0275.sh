#!/usr/bin/env bash
set -euo pipefail

# 0275 — CUDA/OpenMP production build alias.
# This keeps the same CUDA feature set validated through 0274b and pairs it
# with the GPU-primary launch wrapper introduced in 0275.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

OUT=${OUT:-build/src_mpcd_base_cuda_0275} \
  bash scripts/build_src_mpcd_cuda_0274.sh

echo "[0275-cuda-build] Built ${OUT:-build/src_mpcd_base_cuda_0275}"
