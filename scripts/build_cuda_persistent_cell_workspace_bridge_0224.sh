#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

NVCC="${NVCC:-nvcc}"
CUDA_ARCH_FLAGS="${CUDA_ARCH_FLAGS:--arch=sm_89}"
BUILD_DIR="${BUILD_DIR:-build}"
CXXFLAGS_EXTRA="${CXXFLAGS_EXTRA:-}"
OUT="$BUILD_DIR/validate_cuda_persistent_cell_workspace_bridge_0224"

mkdir -p "$BUILD_DIR"

if ! command -v "$NVCC" >/dev/null 2>&1; then
  echo "[0224-build] ERROR: nvcc not found" >&2
  exit 2
fi

echo "[0224-build] root       : $ROOT"
echo "[0224-build] nvcc       : $NVCC"
echo "[0224-build] cuda flags : $CUDA_ARCH_FLAGS"
echo "[0224-build] output     : $OUT"

"$NVCC" -std=c++17 -O3 $CUDA_ARCH_FLAGS $CXXFLAGS_EXTRA \
  -DMPCD_ENABLE_CUDA_PERSISTENT_STEP \
  -DMPCD_ENABLE_CUDA_PARTICLE_STATE \
  -DMPCD_ENABLE_CUDA_CELL_WORKSPACE \
  -Iinclude \
  src/cuda_particle_state.cu \
  src/cuda_cell_workspace.cu \
  src/cuda_persistent_mpcd_step.cu \
  src/main_validate_cuda_persistent_cell_workspace_bridge_0224.cpp \
  src/particle_state.cpp \
  -o "$OUT"
