#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(pwd)}"
NVCC="${NVCC:-nvcc}"
CUDA_ARCH_FLAGS="${CUDA_ARCH_FLAGS:--arch=sm_89}"
mkdir -p "$ROOT/build"
echo "[0232-build] root       : $ROOT"
echo "[0232-build] nvcc       : $NVCC"
echo "[0232-build] cuda flags : $CUDA_ARCH_FLAGS"
"$NVCC" -std=c++17 -O2 $CUDA_ARCH_FLAGS \
  -I"$ROOT/include" \
  "$ROOT/src/cuda_resampling_guard.cu" \
  "$ROOT/src/cuda_resampling_particle_ops.cu" \
  "$ROOT/src/main_validate_cuda_resampling_particle_select_0232.cpp" \
  -o "$ROOT/build/validate_cuda_resampling_particle_select_0232"
echo "[0232-build] output     : build/validate_cuda_resampling_particle_select_0232"
