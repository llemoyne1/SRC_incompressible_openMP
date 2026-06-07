#!/usr/bin/env bash
set -euo pipefail

# 0276 — CUDA/OpenMP build alias for the wall-aware persistent SRC thermostat.
# The feature set is inherited from 0275; only src/cuda_persistent_mpcd_step.cu
# changes in this patch.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

OUT=${OUT:-build/src_mpcd_base_cuda_0276} \
  bash scripts/build_src_mpcd_cuda_0275.sh

echo "[0276-cuda-build] Built ${OUT:-build/src_mpcd_base_cuda_0276}"
