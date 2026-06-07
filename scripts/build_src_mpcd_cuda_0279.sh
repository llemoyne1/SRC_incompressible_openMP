#!/usr/bin/env bash
set -euo pipefail

# 0279 — CUDA/OpenMP build alias for the full-face inlet/outlet thermostat validator.
# No CUDA kernel is changed in 0279. The compiled feature set is inherited from
# 0278/0277/0276; 0279 validates the fused persistent CUDA SRC+thermostat path
# on the open_rect_obstacle_full inlet/outlet case.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

OUT=${OUT:-build/src_mpcd_base_cuda_0279} \
  bash scripts/build_src_mpcd_cuda_0278.sh

echo "[0279-cuda-build] Built ${OUT:-build/src_mpcd_base_cuda_0279}"
