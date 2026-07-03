#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

NVCC=${NVCC:-nvcc}
NVCCFLAGS=${NVCCFLAGS:---std=c++17 -O2}
if [[ -z "${CUDA_ARCH_FLAGS:-}" ]]; then
  CUDA_ARCH_FLAGS="--generate-code=arch=compute_60,code=sm_60 --generate-code=arch=compute_60,code=compute_60"
fi
HOST_OPENMP_FLAG=${HOST_OPENMP_FLAG:--fopenmp}
OUT=${OUT:-build/validate_cuda_resampling_remap_thermal_shadow_0443}

mkdir -p build
if ! command -v "$NVCC" >/dev/null 2>&1; then
  echo "[0443-build] ERROR: nvcc not found" >&2
  exit 2
fi

set -x
"$NVCC" $NVCCFLAGS $CUDA_ARCH_FLAGS \
  -Iinclude \
  -Xcompiler "$HOST_OPENMP_FLAG" \
  src/main_validate_cuda_resampling_remap_thermal_shadow_0443.cu \
  src/particle_state.cpp \
  src/cell_grid.cpp \
  src/fluid_domain.cpp \
  src/weighted_resampling.cpp \
  -o "$OUT"
set +x

echo "[0443-build] Built $OUT"
