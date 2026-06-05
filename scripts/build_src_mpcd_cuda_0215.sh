#!/usr/bin/env bash
set -euo pipefail

# 0215 — CUDA-enabled SRC/MPCD executable with persistent particle-state SRC collision+thermostat path.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

NVCC=${NVCC:-nvcc}
NVCCFLAGS=${NVCCFLAGS:---std=c++17 -O2}
CUDA_ARCH_FLAGS=${CUDA_ARCH_FLAGS:-}
HOST_OPENMP_FLAG=${HOST_OPENMP_FLAG:--fopenmp}
OUT=${OUT:-build/src_mpcd_base_cuda_0215}

mkdir -p build

if ! command -v "$NVCC" >/dev/null 2>&1; then
  echo "[0215-cuda-build] ERROR: nvcc not found. Set NVCC=/path/to/nvcc or load CUDA." >&2
  exit 2
fi

set -x
"$NVCC" $NVCCFLAGS $CUDA_ARCH_FLAGS \
  -DMPCD_ENABLE_CUDA_Q6 \
  -DMPCD_ENABLE_CUDA_CELL_MOMENTS \
  -DMPCD_ENABLE_CUDA_THERMOSTAT \
  -DMPCD_ENABLE_CUDA_SRC_COLLISION \
  -DMPCD_ENABLE_CUDA_PERSISTENT_STEP \
  -Iinclude \
  -Xcompiler "$HOST_OPENMP_FLAG" \
  src/main_src_mpcd_base.cpp \
  src/params_io_base.cpp \
  src/cell_grid.cpp \
  src/boundary_base.cpp \
  src/fluid_domain.cpp \
  src/immersed_solid.cpp \
  src/src_collision.cpp \
  src/thermostat.cpp \
  src/elliptic_projection.cpp \
  src/q6_projection_adapter.cpp \
  src/closed_capacity_response.cpp \
  src/src_mpcd_base.cpp \
  src/runtime_summary.cpp \
  src/particle_state.cpp \
  src/state_smpcd_io.cpp \
  src/weighted_resampling.cpp \
  src/cuda_q6_backend.cu \
  src/cuda_cell_moments.cu \
  src/cuda_cell_thermostat.cu \
  src/cuda_src_collision.cu \
  src/cuda_persistent_mpcd_step.cu \
  -o "$OUT"
set +x

echo "[0215-cuda-build] Built $OUT"
