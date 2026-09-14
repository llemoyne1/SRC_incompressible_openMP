#!/usr/bin/env bash
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT" || exit $?
P=patches/0493x17b_mobile_solids_initialization.patch
[[ -f "$P" ]] || { echo "[0493x17b] missing $P" >&2; exit 2; }
grep -q 'backend=x17a-lagrangian-edge-mesh' src/cuda_q6_resident_0400.cu || {
  echo '[0493x17b] prerequisite absent: apply x17a first' >&2; exit 2; }
if grep -q '0493x17b: with a persistent Lagrangian material boundary' src/params_io_base.cpp; then
  echo '[0493x17b] already applied; checking'
  bash scripts/check_0493x17b_mobile_solids_initialization.sh || exit $?
  exit 0
fi
patch --dry-run -p1 < "$P" || exit $?
patch -p1 < "$P" || exit $?
bash scripts/check_0493x17b_mobile_solids_initialization.sh || exit $?
echo '[0493x17b] APPLY PASS'
