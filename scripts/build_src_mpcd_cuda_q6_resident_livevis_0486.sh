#!/usr/bin/env bash
set -euo pipefail

# 0486 — CUDA resident Q6/resampling build with live visualization enabled.
# Standalone builder: does not depend on the livevis option path of the generic 0400 builder.
# It forces -DMPCD_ENABLE_LIVE_VIS and links GLFW/OpenGL explicitly.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

NVCC=${NVCC:-nvcc}
NVCCFLAGS=${NVCCFLAGS:---std=c++17 -O2}
CUDA_ARCH_FLAGS=${CUDA_ARCH_FLAGS:--arch=sm_89}
HOST_OPENMP_FLAG=${HOST_OPENMP_FLAG:--fopenmp}
OUT=${OUT:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}

if ! command -v "$NVCC" >/dev/null 2>&1; then
  echo "[0486-livevis-build] ERROR: nvcc not found" >&2
  exit 2
fi

LIVEVIS_CFLAGS=()
LIVEVIS_LIBS=()

# Optional hard override, useful if GLFW is installed in a non-standard prefix.
# Example:
#   MPCD_LIVEVIS_CFLAGS='-I/opt/glfw/include'
#   MPCD_LIVEVIS_LIBS='-L/opt/glfw/lib -lglfw -lGL -ldl -lpthread'
if [[ -n "${MPCD_LIVEVIS_CFLAGS:-}" ]]; then
  # shellcheck disable=SC2206
  LIVEVIS_CFLAGS=(${MPCD_LIVEVIS_CFLAGS})
elif command -v pkg-config >/dev/null 2>&1 && pkg-config --exists glfw3; then
  # shellcheck disable=SC2207
  LIVEVIS_CFLAGS=($(pkg-config --cflags glfw3))
fi

if [[ -n "${MPCD_LIVEVIS_LIBS:-}" ]]; then
  # shellcheck disable=SC2206
  LIVEVIS_LIBS=(${MPCD_LIVEVIS_LIBS})
elif command -v pkg-config >/dev/null 2>&1 && pkg-config --exists glfw3; then
  # Dynamic pkg-config GLFW usually returns only -lglfw; keep -lGL explicit.
  # shellcheck disable=SC2207
  LIVEVIS_LIBS=($(pkg-config --libs glfw3) -lGL -ldl -lpthread)
else
  LIVEVIS_LIBS=(-lglfw -lGL -ldl -lpthread)
fi

mkdir -p build

echo "[0486-livevis-build] OUT=$OUT"
echo "[0486-livevis-build] NVCC=$NVCC"
echo "[0486-livevis-build] NVCCFLAGS=$NVCCFLAGS"
echo "[0486-livevis-build] CUDA_ARCH_FLAGS=$CUDA_ARCH_FLAGS"
echo "[0486-livevis-build] HOST_OPENMP_FLAG=$HOST_OPENMP_FLAG"
echo "[0486-livevis-build] LIVEVIS_CFLAGS=${LIVEVIS_CFLAGS[*]:-<none>}"
echo "[0486-livevis-build] LIVEVIS_LIBS=${LIVEVIS_LIBS[*]}"

set -x
"$NVCC" $NVCCFLAGS $CUDA_ARCH_FLAGS \
  -DMPCD_ENABLE_LIVE_VIS \
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
  -DMPCD_ENABLE_CUDA_DARCY_BRINKMAN_0343 \
  -DMPCD_ENABLE_CUDA_Q6_RESIDENT_0400 \
  -Iinclude \
  "${LIVEVIS_CFLAGS[@]}" \
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
  src/cuda_species_mass_closure_0490i.cu \
  src/cuda_species_transfer_plan_0490k.cu \
  src/cuda_species_resampling_fast_path_0490m.cu \
  src/state_smpcd_io.cpp \
  src/weighted_resampling.cpp \
  src/cuda_shared_particle_state_0251.cpp \
  src/live_visualization_0335.cpp \
  src/filtered_field_recorder_0432.cpp \
  src/cuda_resampling_persistent_active_path_0240.cpp \
  src/cuda_q6_backend.cu \
  src/cuda_q6_resident_0400.cu \
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
  src/cuda_resampling_pipeline_shadow_0445.cu \
  src/cuda_streaming_periodic_0245.cu \
  src/cuda_streaming_wall_simple_0246.cu \
  src/cuda_immersed_rectangle_0247.cu \
  src/cuda_immersed_circle_0284.cu \
  src/cuda_streaming_piston_0247b.cu \
  src/cuda_inlet_outlet_fullface_0249a.cu \
  src/cuda_inlet_outlet_segmented_0249b.cu \
  src/cuda_classic_src_io_resident_0263.cu \
  src/cuda_darcy_brinkman_0343.cu \
  src/cuda_live_field_0337.cu \
  "${LIVEVIS_LIBS[@]}" \
  -o "$OUT"
set +x

echo "[0486-livevis-build] Built $OUT"
echo "[0486-livevis-build] Dynamic livevis deps:"
ldd "$OUT" | grep -E 'glfw|GL|X11|wayland' || true
