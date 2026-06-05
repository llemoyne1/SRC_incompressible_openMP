#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(pwd)}"
NVCC="${NVCC:-nvcc}"
CUDA_ARCH_FLAGS="${CUDA_ARCH_FLAGS:--arch=sm_89}"
mkdir -p "$ROOT/build"
echo "[0228-build] root       : $ROOT"
echo "[0228-build] nvcc       : $NVCC"
echo "[0228-build] cuda flags : $CUDA_ARCH_FLAGS"
"$NVCC" -O3 -std=c++17 $CUDA_ARCH_FLAGS \
  -I"$ROOT/include" \
  "$ROOT/src/cuda_resampling_guard.cu" \
  "$ROOT/src/main_validate_cuda_resampling_plan_0228.cpp" \
  -o "$ROOT/build/validate_cuda_resampling_plan_0228"
echo "[0228-build] output     : build/validate_cuda_resampling_plan_0228"
