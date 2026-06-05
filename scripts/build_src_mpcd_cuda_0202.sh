#!/usr/bin/env bash
set -euo pipefail

# 0202 — CUDA-enabled SRC/MPCD executable with Q6 CUDA and optional
# active CUDA cell-moments deposit with persistent buffers/fast paths. CPU/OpenMP remains the default; set
# MPCD_CUDA_CELL_MOMENTS_USE=1 to let CUDA replace the collision deposit.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

NVCC=${NVCC:-nvcc}
NVCCFLAGS=${NVCCFLAGS:---std=c++17 -O2}
CUDA_ARCH_FLAGS=${CUDA_ARCH_FLAGS:-}
HOST_OPENMP_FLAG=${HOST_OPENMP_FLAG:--fopenmp}
OUT=${OUT:-build/src_mpcd_base_cuda_0202}

mkdir -p build

if ! command -v "$NVCC" >/dev/null 2>&1; then
  echo "[0202-cuda-build] ERROR: nvcc not found. Set NVCC=/path/to/nvcc or load CUDA." >&2
  exit 2
fi

set -x
"$NVCC" $NVCCFLAGS $CUDA_ARCH_FLAGS \
  -DMPCD_ENABLE_CUDA_Q6 \
  -DMPCD_ENABLE_CUDA_CELL_MOMENTS \
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
  src/cuda_resampling_persistent_active_path_0240.cpp \
  src/cuda_q6_backend.cu \
  src/cuda_cell_moments.cu \
  -o "$OUT"
set +x

echo "[0202-cuda-build] Built $OUT"
