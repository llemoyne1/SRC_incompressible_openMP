#!/usr/bin/env bash
set -euo pipefail

# 0349/topo: qualitative NACA 4-digit incidence sweep.
# This is not yet a calibrated aerodynamic polar; it validates that the
# chi_file generator and Darcy force proxies respond consistently to AoA.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

Lx="${Lx:-1.5}"; Ly="${Ly:-0.4}"; NX="${NX:-360}"; NY="${NY:-96}"
TAG_PREFIX="${TAG_PREFIX:-topo_darcy_naca_sweep_0349}"
RUN_ROOT="runs/${TAG_PREFIX}"
CHI_DIR="${RUN_ROOT}/chi"
mkdir -p "$CHI_DIR" "${RUN_ROOT}/logs"

AOAS="${AOAS:--8 -4 0 4 8}"
NACA_CODE="${NACA_CODE:-0012}"
NACA_CHORD="${NACA_CHORD:-0.22}"
CX="${CX:-0.55}"
CY="${CY:-0.20}"
INTERFACE_WIDTH="${INTERFACE_WIDTH:-0.006}"
STEPS="${STEPS:-1800}"
TAIL_FRACTION="${TAIL_FRACTION:-0.5}"

summary="${RUN_ROOT}/naca_sweep_0349_summary.csv"
echo "naca,aoaDeg,chiFile,benchmarkCsv,windowStatsCsv" > "$summary"

for aoa in $AOAS; do
  safe_aoa="${aoa//-/m}"
  safe_aoa="${safe_aoa//./p}"
  tag="${TAG_PREFIX}_${NACA_CODE}_a${safe_aoa}"
  chi="${CHI_DIR}/naca${NACA_CODE}_aoa${safe_aoa}_${NX}x${NY}.f32"
  echo "[0349-naca] generating naca=$NACA_CODE aoa=$aoa chi=$chi"
  python3 scripts/generate_topo_chi_field_0345.py \
    --mode naca4_airfoil --naca "$NACA_CODE" --chord "$NACA_CHORD" \
    --airfoil-cx "$CX" --airfoil-cy "$CY" --aoa-deg "$aoa" \
    --out "$chi" --Nx "$NX" --Ny "$NY" --Lx "$Lx" --Ly "$Ly" \
    --interface-width "$INTERFACE_WIDTH" \
    | tee "${RUN_ROOT}/logs/generate_aoa${safe_aoa}.log"

  BIN="${BIN:-build/src_mpcd_base_cuda_topo_0348a}" \
  Lx="$Lx" Ly="$Ly" NX="$NX" NY="$NY" \
  DARCY_CHI_MODE=file DARCY_CHI_FILE="$chi" DARCY_CHI_FILE_FORMAT=float32 \
  DARCY_ALPHA_MAX="${DARCY_ALPHA_MAX:-320}" DARCY_Q="${DARCY_Q:-0.1}" DARCY_COST_EVERY="${DARCY_COST_EVERY:-20}" \
  TOPO_BENCHMARK_ENABLE=1 TOPO_BENCHMARK_EVERY="${TOPO_BENCHMARK_EVERY:-20}" \
  TOPO_BENCHMARK_FORCE_ENABLE=1 TOPO_BENCHMARK_DRAG_LIFT_ENABLE=1 \
  TOPO_BENCHMARK_FLOW_DIR_X=1 TOPO_BENCHMARK_FLOW_DIR_Y=0 \
  TOPO_BENCHMARK_LIFT_DIR_X=0 TOPO_BENCHMARK_LIFT_DIR_Y=1 \
  GAMMA="${GAMMA:-40}" KBT="${KBT:-0.1}" U0="${U0:-0.5}" STEPS="$STEPS" \
  LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-0}" LIVE_VIS_NX="${LIVE_VIS_NX:-$NX}" LIVE_VIS_NY="${LIVE_VIS_NY:-$NY}" \
  FORCE_REBUILD="${FORCE_REBUILD:-0}" CLEAN_RUN_ROOT=1 TAG="$tag" \
    bash scripts/run_topo_darcy_brinkman_viz_0343.sh

  bench="runs/${tag}/output/topo_benchmark_0348.csv"
  stats="runs/${tag}/topo_benchmark_window_stats_0348b.csv"
  python3 scripts/analyze_topo_benchmark_window_0348b.py \
    --csv "$bench" --out "$stats" --tail-fraction "$TAIL_FRACTION"
  printf '%s,%s,%s,%s,%s\n' "$NACA_CODE" "$aoa" "$chi" "$bench" "$stats" >> "$summary"
done

echo "[0349-naca] summary=$summary"
cat "$summary"
