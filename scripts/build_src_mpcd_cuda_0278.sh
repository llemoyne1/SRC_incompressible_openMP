#!/usr/bin/env bash
set -euo pipefail

# 0278 — CUDA/OpenMP build alias for the piston/mobile-wall thermostat validator.
# No CUDA kernel is changed in 0278. The compiled feature set is inherited from
# 0277/0276; 0278 validates the post-CPU-stage persistent CUDA thermostat path
# on piston_virial_full, where Q6/resampling/closed-capacity virial may still
# run between SRC collision and thermostat.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

OUT=${OUT:-build/src_mpcd_base_cuda_0278} \
  bash scripts/build_src_mpcd_cuda_0277.sh

echo "[0278-cuda-build] Built ${OUT:-build/src_mpcd_base_cuda_0278}"
