#!/usr/bin/env bash
set -euo pipefail

# 0350/topo: run or reuse a NACA sweep, then write a compact polar-proxy CSV.
# The solver is unchanged.  LIFT_SIGN defaults to -1 so positive AoA maps to
# positive lift for the current Darcy proxy convention observed in 0349.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

TAG_PREFIX="${TAG_PREFIX:-topo_darcy_naca_sweep_0350}"
RUN_FIRST="${RUN_FIRST:-1}"
LIFT_SIGN="${LIFT_SIGN:--1}"
DRAG_SIGN="${DRAG_SIGN:-1}"
SUMMARY="${SUMMARY:-runs/${TAG_PREFIX}/naca_sweep_0349_summary.csv}"
OUT="${OUT:-runs/${TAG_PREFIX}/naca_polar_proxy_0350.csv}"

if [[ "$RUN_FIRST" == "1" || "$RUN_FIRST" == "true" || "$RUN_FIRST" == "TRUE" ]]; then
  TAG_PREFIX="$TAG_PREFIX" \
  BIN="${BIN:-build/src_mpcd_base_cuda_topo_0348a}" \
  AOAS="${AOAS:--8 -4 0 4 8}" \
  NACA_CODE="${NACA_CODE:-0012}" \
  NACA_CHORD="${NACA_CHORD:-0.22}" \
  LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-0}" \
  STEPS="${STEPS:-1800}" \
  FORCE_REBUILD="${FORCE_REBUILD:-0}" \
    bash scripts/run_topo_darcy_naca_sweep_0349.sh
fi

python3 scripts/analyze_topo_naca_polar_proxy_0350.py \
  --summary "$SUMMARY" \
  --out "$OUT" \
  --lift-sign "$LIFT_SIGN" \
  --drag-sign "$DRAG_SIGN"

echo "[0350-naca-polar] out=$OUT"
cat "$OUT"
