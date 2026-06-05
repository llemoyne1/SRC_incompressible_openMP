#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

NVCC="${NVCC:-nvcc}"
CUDA_ARCH_FLAGS="${CUDA_ARCH_FLAGS:--arch=sm_89}"
BUILD_DIR="${BUILD_DIR:-build}"
CXXFLAGS_EXTRA="${CXXFLAGS_EXTRA:-}"

mkdir -p "$BUILD_DIR"

echo "[0209-build] root       : $ROOT"
echo "[0209-build] nvcc       : $NVCC"
echo "[0209-build] cuda flags : $CUDA_ARCH_FLAGS"
echo "[0209-build] output     : $BUILD_DIR/validate_cuda_src_collision_0209"

"$NVCC" -std=c++17 -O3 $CUDA_ARCH_FLAGS $CXXFLAGS_EXTRA \
  -DMPCD_ENABLE_CUDA_SRC_COLLISION \
  -Iinclude \
  src/cuda_src_collision.cu \
  src/main_validate_cuda_src_collision_0209.cpp \
  src/particle_state.cpp \
  -o "$BUILD_DIR/validate_cuda_src_collision_0209"
