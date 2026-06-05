#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

NVCC="${NVCC:-nvcc}"
CUDA_ARCH_FLAGS="${CUDA_ARCH_FLAGS:--arch=sm_89}"
BUILD_DIR="${BUILD_DIR:-build}"
CXXFLAGS_EXTRA="${CXXFLAGS_EXTRA:-}"

mkdir -p "$BUILD_DIR"

echo "[0205-build] root       : $ROOT"
echo "[0205-build] nvcc       : $NVCC"
echo "[0205-build] cuda flags : $CUDA_ARCH_FLAGS"
echo "[0205-build] output     : $BUILD_DIR/validate_cuda_cell_thermostat_0205"

"$NVCC" -std=c++17 -O3 $CUDA_ARCH_FLAGS $CXXFLAGS_EXTRA \
  -DMPCD_ENABLE_CUDA_THERMOSTAT \
  -Iinclude \
  src/cuda_cell_thermostat.cu \
  src/main_validate_cuda_cell_thermostat_0205.cpp \
  src/thermostat.cpp \
  src/particle_state.cpp \
  -o "$BUILD_DIR/validate_cuda_cell_thermostat_0205"
