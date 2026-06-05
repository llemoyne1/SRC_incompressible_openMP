#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

NVCC=${NVCC:-nvcc}
NVCCFLAGS=${NVCCFLAGS:---std=c++17 -O2}
# Leave users free to override the target architecture, but do not let nvcc
# silently fall back to an old default architecture: cuda_cell_moments.cu uses
# double precision atomics, native from sm_60 onward.  The compute_60 PTX fallback
# keeps the binary usable on newer devices when the exact SM is not specified.
if [[ -z "${CUDA_ARCH_FLAGS:-}" ]]; then
  CUDA_ARCH_FLAGS="--generate-code=arch=compute_60,code=sm_60 --generate-code=arch=compute_60,code=compute_60"
fi
HOST_OPENMP_FLAG=${HOST_OPENMP_FLAG:--fopenmp}
OUT=${OUT:-build/src_mpcd_base_cuda_0241}

mkdir -p build
if ! command -v "$NVCC" >/dev/null 2>&1; then
  echo "[0241-cuda-build] ERROR: nvcc not found" >&2
  exit 2
fi

set -x
"$NVCC" $NVCCFLAGS $CUDA_ARCH_FLAGS \
  -DMPCD_ENABLE_CUDA_Q6 \
  -DMPCD_ENABLE_CUDA_CELL_MOMENTS \
  -DMPCD_ENABLE_CUDA_THERMOSTAT \
  -DMPCD_ENABLE_CUDA_SRC_COLLISION \
  -DMPCD_ENABLE_CUDA_PERSISTENT_STEP \
  -DMPCD_ENABLE_CUDA_PARTICLE_STATE \
  -DMPCD_ENABLE_CUDA_CELL_WORKSPACE \
  -DMPCD_ENABLE_CUDA_RESAMPLING \
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
  src/cuda_cell_thermostat.cu \
  src/cuda_src_collision.cu \
  src/cuda_persistent_mpcd_step.cu \
  src/cuda_particle_state.cu \
  src/cuda_cell_workspace.cu \
  src/cuda_resampling_guard.cu \
  src/cuda_resampling_particle_ops.cu \
  -o "$OUT"
set +x

echo "[0241-cuda-build] Built $OUT"
