#!/usr/bin/env bash
set -euo pipefail

# 0285 — CUDA immersed-circle + inlet/outlet SRC classic build.
# The feature set builds on 0272b and trims collision-wrapper/per-step CPU overheads while preserving the classic-only validation scope and future Q6/resampling reactivation paths.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

NVCC=${NVCC:-nvcc}
NVCCFLAGS=${NVCCFLAGS:---std=c++17 -O2}
if [[ -z "${CUDA_ARCH_FLAGS:-}" ]]; then
  CUDA_ARCH_FLAGS="--generate-code=arch=compute_60,code=sm_60 --generate-code=arch=compute_60,code=compute_60"
fi
HOST_OPENMP_FLAG=${HOST_OPENMP_FLAG:--fopenmp}
OUT=${OUT:-build/src_mpcd_base_cuda_0285}

mkdir -p build
if ! command -v "$NVCC" >/dev/null 2>&1; then
  echo "[0285-cuda-build] ERROR: nvcc not found" >&2
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
  -DMPCD_ENABLE_CUDA_STREAMING_0245 \
  -DMPCD_ENABLE_CUDA_STREAMING_0246 \
  -DMPCD_ENABLE_CUDA_IMMERSED_RECTANGLE_0247 \
  -DMPCD_ENABLE_CUDA_IMMERSED_CIRCLE_0284 \
  -DMPCD_ENABLE_CUDA_STREAMING_PISTON_0247B \
  -DMPCD_ENABLE_CUDA_INLET_OUTLET_FULLFACE_0249A \
  -DMPCD_ENABLE_CUDA_INLET_OUTLET_SEGMENTED_0249B \
  -DMPCD_ENABLE_CUDA_CLASSIC_SRC_IO_RESIDENT_0263 \
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
  src/cuda_shared_particle_state_0251.cpp \
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
  src/cuda_streaming_periodic_0245.cu \
  src/cuda_streaming_wall_simple_0246.cu \
  src/cuda_immersed_rectangle_0247.cu \
  src/cuda_immersed_circle_0284.cu \
  src/cuda_streaming_piston_0247b.cu \
  src/cuda_inlet_outlet_fullface_0249a.cu \
  src/cuda_inlet_outlet_segmented_0249b.cu \
  src/cuda_classic_src_io_resident_0263.cu \
  -o "$OUT"
set +x

echo "[0285-cuda-build] Built $OUT"
