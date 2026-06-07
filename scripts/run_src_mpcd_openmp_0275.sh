#!/usr/bin/env bash
set -euo pipefail

# Explicit OpenMP/CPU opt-out wrapper for the SRC_GPU branch.
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
MPCD_BACKEND=openmp exec scripts/run_src_mpcd_cuda_primary_0275.sh "$@"
