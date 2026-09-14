#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"
P=patches/0493x16q_chi_overlap_deadzone_fix.patch
SRC=src/cuda_q6_resident_0400.cu
[[ -f "$P" ]] || { echo "[0493x16q] missing $P" >&2; exit 2; }
[[ -f "$SRC" ]] || { echo "[0493x16q] missing $SRC" >&2; exit 2; }
if grep -q 'overlapTol=x16q-chi-1e-10h' "$SRC"; then
  echo '[0493x16q] already applied; checking'
  bash scripts/check_0493x16q_chi_overlap_deadzone_fix.sh
  exit 0
fi
for marker in 'q2Topology=x16p-boundary-root-trace' 'q2Edges=x16o-q2-edge-roots' 'q2Owner=x16n-dual-square-clipped' 'q2Root=x16m-bisection-1e-8cell'; do
  grep -q "$marker" "$SRC" || { echo "[0493x16q] prerequisite absent: $marker" >&2; exit 2; }
done
patch --dry-run -p1 < "$P"
patch -p1 < "$P"
bash scripts/check_0493x16q_chi_overlap_deadzone_fix.sh
echo '[0493x16q] APPLY PASS'
