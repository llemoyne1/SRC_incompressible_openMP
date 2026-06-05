#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
NVCC=${NVCC:-nvcc}
NVCCFLAGS=${NVCCFLAGS:---std=c++17 -O2}
CUDA_ARCH_FLAGS=${CUDA_ARCH_FLAGS:-}
OUT=${OUT:-build/validate_cuda_resampling_persistent_state_ops_0239}
mkdir -p build
if ! command -v "$NVCC" >/dev/null 2>&1; then
  echo "[0239-cuda-build] ERROR: nvcc not found" >&2
  exit 2
fi
set -x
"$NVCC" $NVCCFLAGS $CUDA_ARCH_FLAGS \
  -DMPCD_ENABLE_CUDA_PARTICLE_STATE \
  -DMPCD_ENABLE_CUDA_RESAMPLING \
  -Iinclude \
  src/main_validate_cuda_resampling_persistent_state_ops_0239.cpp \
  src/cuda_particle_state.cu \
  src/cuda_resampling_particle_ops.cu \
  src/particle_state.cpp \
  -o "$OUT"
set +x
echo "[0239-cuda-build] Built $OUT"
