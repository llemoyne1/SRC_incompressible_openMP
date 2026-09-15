#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"
P=patches/0493x17c_elastic_membrane_fsi.patch
[[ -f "$P" ]] || { echo "[0493x17c] missing $P" >&2; exit 2; }

grep -q 'backend=x17a-lagrangian-edge-mesh' src/cuda_q6_resident_0400.cu || {
  echo '[0493x17c] prerequisite absent: x17a Lagrangian boundary is required' >&2; exit 2; }
grep -q '0493x17b: with a persistent Lagrangian material boundary' src/params_io_base.cpp || {
  echo '[0493x17c] prerequisite absent: apply qualified x17b initialization closure first' >&2; exit 2; }

if grep -q '0493x17c-membrane' src/cuda_q6_resident_0400.cu && \
   grep -q 'chiSolidMembraneStretchStiffness' include/simulation_params.h; then
  echo '[0493x17c] already applied; checking'
  bash scripts/check_0493x17c_elastic_membrane_fsi.sh
  exit 0
fi

patch --dry-run -p1 < "$P"
patch -p1 < "$P"
bash scripts/check_0493x17c_elastic_membrane_fsi.sh
echo '[0493x17c] APPLY PASS'
