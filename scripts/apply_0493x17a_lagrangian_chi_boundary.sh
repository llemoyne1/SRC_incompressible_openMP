#!/usr/bin/env bash
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT" || exit $?
P=patches/0493x17a_lagrangian_chi_boundary.patch
SRC=src/cuda_q6_resident_0400.cu
[[ -f "$P" ]] || { echo "[0493x17a] missing $P" >&2; exit 2; }
[[ -f "$SRC" ]] || { echo "[0493x17a] missing $SRC" >&2; exit 2; }
if grep -q 'backend=x17a-lagrangian-edge-mesh' "$SRC"; then
  echo '[0493x17a] already applied; checking'
  bash scripts/check_0493x17a_lagrangian_boundary.sh || exit $?
  exit 0
fi
grep -q 'overlapTol=x16q-chi-1e-10h' "$SRC" || {
  echo '[0493x17a] prerequisite absent: expected applied x16q baseline' >&2; exit 2; }
grep -q 'q2Topology=x16p-boundary-root-trace' "$SRC" || {
  echo '[0493x17a] prerequisite absent: expected x16p topology baseline' >&2; exit 2; }
patch --dry-run -p1 < "$P" || exit $?
patch -p1 < "$P" || exit $?
bash scripts/check_0493x17a_lagrangian_boundary.sh || exit $?
echo '[0493x17a] APPLY PASS'
