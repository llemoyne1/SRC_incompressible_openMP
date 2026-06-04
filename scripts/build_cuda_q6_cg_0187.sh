#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

NVCC=${NVCC:-nvcc}
NVCCFLAGS=${NVCCFLAGS:--std=c++17 -O2}
CUDA_ARCH_FLAGS=${CUDA_ARCH_FLAGS:-}

mkdir -p build

if ! command -v "$NVCC" >/dev/null 2>&1; then
  echo "[0187-cuda-cg-build] ERROR: nvcc not found. Set NVCC=/path/to/nvcc or load CUDA." >&2
  exit 2
fi

set -x
"$NVCC" $NVCCFLAGS $CUDA_ARCH_FLAGS -Iinclude \
  src/main_validate_cuda_q6_cg_0187.cpp \
  src/cuda_q6_backend.cu \
  -o build/validate_cuda_q6_cg_0187
set +x

echo "[0187-cuda-cg-build] Built build/validate_cuda_q6_cg_0187"
