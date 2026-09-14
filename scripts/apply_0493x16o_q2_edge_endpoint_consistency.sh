#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"
P=patches/0493x16o_q2_edge_endpoint_consistency.patch
SRC=src/cuda_q6_resident_0400.cu
[[ -f "$P" ]] || { echo "[0493x16o] missing $P" >&2; exit 2; }
[[ -f "$SRC" ]] || { echo "[0493x16o] missing $SRC" >&2; exit 2; }
if grep -q 'q2Edges=x16o-q2-edge-roots' "$SRC"; then
  echo '[0493x16o] already applied; checking'
  bash scripts/check_0493x16o_q2_edge_endpoint_consistency.sh
  exit 0
fi
for marker in 'q2Owner=x16n-dual-square-clipped' 'q2Root=x16m-bisection-1e-8cell'; do
  grep -q "$marker" "$SRC" || { echo "[0493x16o] prerequisite absent: $marker" >&2; exit 2; }
done
patch --dry-run -p1 < "$P"
patch -p1 < "$P"
bash scripts/check_0493x16o_q2_edge_endpoint_consistency.sh
echo '[0493x16o] APPLY PASS'
