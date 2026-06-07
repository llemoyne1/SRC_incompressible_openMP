#!/usr/bin/env bash
set -euo pipefail

# 0277 — CUDA/OpenMP build alias for the solid/obstacle-aware persistent SRC thermostat.
# The compiled feature set is inherited from 0276. 0277 adds a solid-rectangle
# validator and does not change the CUDA kernels.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

OUT=${OUT:-build/src_mpcd_base_cuda_0277} \
  bash scripts/build_src_mpcd_cuda_0276.sh

echo "[0277-cuda-build] Built ${OUT:-build/src_mpcd_base_cuda_0277}"
