#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

NVCC="${NVCC:-nvcc}"
CUDA_ARCH_FLAGS="${CUDA_ARCH_FLAGS:--arch=sm_89}"
BUILD_DIR="${BUILD_DIR:-build}"
CXXFLAGS_EXTRA="${CXXFLAGS_EXTRA:-}"

mkdir -p "$BUILD_DIR"

if ! command -v "$NVCC" >/dev/null 2>&1; then
  echo "[0212-build] ERROR: nvcc not found" >&2
  exit 2
fi

echo "[0212-build] root       : $ROOT"
echo "[0212-build] nvcc       : $NVCC"
echo "[0212-build] cuda flags : $CUDA_ARCH_FLAGS"
echo "[0212-build] output     : $BUILD_DIR/validate_cuda_persistent_mpcd_step_0212"

"$NVCC" -std=c++17 -O3 $CUDA_ARCH_FLAGS $CXXFLAGS_EXTRA \
  -DMPCD_ENABLE_CUDA_PERSISTENT_STEP \
  -Iinclude \
  src/cuda_persistent_mpcd_step.cu \
  src/main_validate_cuda_persistent_mpcd_step_0212.cpp \
  src/particle_state.cpp \
  -o "$BUILD_DIR/validate_cuda_persistent_mpcd_step_0212"
