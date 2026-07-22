#!/usr/bin/env bash
set -euo pipefail

# 0315b — CUDA SRC/MPCD build for active-fluid physical-loop validation.
# Same source set as 0314; OUT defaults to a distinct binary so that an already
# built 0314/reference executable can be kept side-by-side.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

NVCC=${NVCC:-nvcc}
NVCCFLAGS=${NVCCFLAGS:---std=c++17 -O2}
if [[ -z "${CUDA_ARCH_FLAGS:-}" ]]; then
  CUDA_ARCH_FLAGS="--generate-code=arch=compute_60,code=sm_60 --generate-code=arch=compute_60,code=compute_60"
fi
HOST_OPENMP_FLAG=${HOST_OPENMP_FLAG:--fopenmp}
OUT=${OUT:-build/src_mpcd_base_cuda_0315b}

truthy_0335() {
  case "${1:-0}" in 1|true|TRUE|yes|YES|on|ON|enable|enabled) return 0 ;; *) return 1 ;; esac
}

LIVE_VIS_DEFS=()
LIVE_VIS_LIBS=()
if truthy_0335 "${MPCD_ENABLE_LIVE_VIS:-0}"; then
  LIVE_VIS_DEFS=(-DMPCD_ENABLE_LIVE_VIS)
  LIVE_VIS_LIBS=(-lglfw -lGL)
fi

mkdir -p build
if ! command -v "$NVCC" >/dev/null 2>&1; then
  echo "[0315b-cuda-build] ERROR: nvcc not found" >&2
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
  "${LIVE_VIS_DEFS[@]}" \
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
  src/species_registry.cpp \
  src/species_cell_fields_0490b.cpp \
  src/cuda_species_cell_fields_0490h.cu \
  src/state_smpcd_io.cpp \
  src/weighted_resampling.cpp \
  src/cuda_shared_particle_state_0251.cpp \
  src/live_visualization_0335.cpp \
  src/filtered_field_recorder_0432.cpp \
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
  src/cuda_resampling_support_survey_0295.cu \
  src/cuda_resampling_mass_recondition_0296.cu \
  src/cuda_resampling_population_guard_0297.cu \
  src/cuda_resampling_adaptive_flag_0304.cu \
  src/cuda_streaming_periodic_0245.cu \
  src/cuda_streaming_wall_simple_0246.cu \
  src/cuda_immersed_rectangle_0247.cu \
  src/cuda_immersed_circle_0284.cu \
  src/cuda_streaming_piston_0247b.cu \
  src/cuda_inlet_outlet_fullface_0249a.cu \
  src/cuda_inlet_outlet_segmented_0249b.cu \
  src/cuda_classic_src_io_resident_0263.cu \
  src/cuda_live_field_0337.cu \
  "${LIVE_VIS_LIBS[@]}" \
  -o "$OUT"
set +x

echo "[0315b-cuda-build] Built $OUT"
