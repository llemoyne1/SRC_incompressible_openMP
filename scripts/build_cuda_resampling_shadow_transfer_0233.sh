#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(pwd)}"
NVCC="${NVCC:-nvcc}"
CUDA_ARCH_FLAGS="${CUDA_ARCH_FLAGS:--arch=sm_89}"
mkdir -p "$ROOT/build"
echo "[0233-build] root       : $ROOT"
echo "[0233-build] nvcc       : $NVCC"
echo "[0233-build] cuda flags : $CUDA_ARCH_FLAGS"
"$NVCC" -std=c++17 -O2 $CUDA_ARCH_FLAGS \
  -I"$ROOT/include" \
  "$ROOT/src/cuda_resampling_guard.cu" \
  "$ROOT/src/cuda_resampling_particle_ops.cu" \
  "$ROOT/src/main_validate_cuda_resampling_shadow_transfer_0233.cpp" \
  -o "$ROOT/build/validate_cuda_resampling_shadow_transfer_0233"
echo "[0233-build] output     : build/validate_cuda_resampling_shadow_transfer_0233"
