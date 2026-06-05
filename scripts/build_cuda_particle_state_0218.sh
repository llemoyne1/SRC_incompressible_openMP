#!/usr/bin/env bash
set -euo pipefail

# 0218 — standalone persistent CUDA particle-state manager validator.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

NVCC=${NVCC:-nvcc}
NVCCFLAGS=${NVCCFLAGS:---std=c++17 -O2}
CUDA_ARCH_FLAGS=${CUDA_ARCH_FLAGS:-}
OUT=${OUT:-build/validate_cuda_particle_state_0218}

mkdir -p build

if ! command -v "$NVCC" >/dev/null 2>&1; then
  echo "[0218-build] ERROR: nvcc not found. Set NVCC=/path/to/nvcc or load CUDA." >&2
  exit 2
fi

echo "[0218-build] root       : $ROOT"
echo "[0218-build] nvcc       : $NVCC"
echo "[0218-build] cuda flags : $CUDA_ARCH_FLAGS"
echo "[0218-build] output     : $OUT"

set -x
"$NVCC" $NVCCFLAGS $CUDA_ARCH_FLAGS \
  -DMPCD_ENABLE_CUDA_PARTICLE_STATE \
  -Iinclude \
  src/main_validate_cuda_particle_state_0218.cpp \
  src/cuda_particle_state.cu \
  src/particle_state.cpp \
  -o "$OUT"
set +x

