#!/usr/bin/env bash
set -euo pipefail

# 0312 build wrapper.  The audit itself is independent of demo scripts; the
# binary is the consolidated CUDA SRC/resampling build from 0308.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

OUT=${OUT:-build/src_mpcd_base_cuda_0312}
if [[ -x scripts/build_src_mpcd_cuda_0308.sh ]]; then
  OUT="$OUT" CUDA_ARCH_FLAGS="${CUDA_ARCH_FLAGS:-}" bash scripts/build_src_mpcd_cuda_0308.sh
else
  echo "[0312-build] ERROR: scripts/build_src_mpcd_cuda_0308.sh not found" >&2
  exit 2
fi
