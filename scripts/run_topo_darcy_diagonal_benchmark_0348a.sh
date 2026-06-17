#!/usr/bin/env bash
set -euo pipefail

# 0348a/topo: diagonal-channel benchmark run with optional cell-based
# Darcy force / drag / lift observables enabled.  This reuses the validated
# chi_file path and does not add section/profile diagnostics.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

Lx="${Lx:-1.0}"; Ly="${Ly:-1.0}"; NX="${NX:-256}"; NY="${NY:-256}"
TAG="${TAG:-topo_darcy_diagonal_benchmark_0348a}"
RUN_ROOT="runs/${TAG}"
CHI_DIR="${CHI_DIR:-${RUN_ROOT}/chi}"
CHI_FILE="${CHI_FILE:-${CHI_DIR}/diagonal_channel_${NX}x${NY}.f32}"

INLET_Y="${INLET_Y:-0.78}"
OUTLET_X="${OUTLET_X:-0.82}"
PIPE_WIDTH="${PIPE_WIDTH:-0.14}"
DARCY_INTERFACE_WIDTH="${DARCY_INTERFACE_WIDTH:-0.015}"

# The diagonal reference flow direction is from (0,inlet_y) to (outlet_x,0).
# The code normalizes these vectors before projecting drag/lift.
FLOW_DIR_X="${FLOW_DIR_X:-$OUTLET_X}"
FLOW_DIR_Y="${FLOW_DIR_Y:--$INLET_Y}"
LIFT_DIR_X="${LIFT_DIR_X:-$INLET_Y}"
LIFT_DIR_Y="${LIFT_DIR_Y:-$OUTLET_X}"

mkdir -p "$CHI_DIR" "${RUN_ROOT}/logs"
python3 scripts/generate_topo_chi_field_0345.py \
  --mode diagonal_channel --out "$CHI_FILE" \
  --Nx "$NX" --Ny "$NY" --Lx "$Lx" --Ly "$Ly" \
  --inlet-y "$INLET_Y" --outlet-x "$OUTLET_X" \
  --pipe-width "$PIPE_WIDTH" --interface-width "$DARCY_INTERFACE_WIDTH" \
  | tee "${RUN_ROOT}/logs/generate_diagonal_benchmark_0348a.log"

BIN="${BIN:-build/src_mpcd_base_cuda_topo_0345}" \
Lx="$Lx" Ly="$Ly" NX="$NX" NY="$NY" \
DARCY_CHI_MODE=file DARCY_CHI_FILE="$CHI_FILE" DARCY_CHI_FILE_FORMAT=float32 \
DARCY_ALPHA_MAX="${DARCY_ALPHA_MAX:-320}" DARCY_Q="${DARCY_Q:-0.1}" DARCY_COST_EVERY="${DARCY_COST_EVERY:-20}" \
TOPO_BENCHMARK_ENABLE="${TOPO_BENCHMARK_ENABLE:-1}" \
TOPO_BENCHMARK_EVERY="${TOPO_BENCHMARK_EVERY:-20}" \
TOPO_BENCHMARK_FILENAME="${TOPO_BENCHMARK_FILENAME:-topo_benchmark_0348.csv}" \
TOPO_BENCHMARK_FORCE_ENABLE="${TOPO_BENCHMARK_FORCE_ENABLE:-1}" \
TOPO_BENCHMARK_DRAG_LIFT_ENABLE="${TOPO_BENCHMARK_DRAG_LIFT_ENABLE:-1}" \
TOPO_BENCHMARK_FLOW_DIR_X="$FLOW_DIR_X" \
TOPO_BENCHMARK_FLOW_DIR_Y="$FLOW_DIR_Y" \
TOPO_BENCHMARK_LIFT_DIR_X="$LIFT_DIR_X" \
TOPO_BENCHMARK_LIFT_DIR_Y="$LIFT_DIR_Y" \
GAMMA="${GAMMA:-40}" KBT="${KBT:-0.1}" U0="${U0:-0.5}" STEPS="${STEPS:-3000}" \
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-0}" LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-chi}" LIVE_VIS_CLIP="${LIVE_VIS_CLIP:-1}" \
LIVE_VIS_NX="${LIVE_VIS_NX:-$NX}" LIVE_VIS_NY="${LIVE_VIS_NY:-$NY}" LIVE_VIS_SMOOTH_PASSES="${LIVE_VIS_SMOOTH_PASSES:-0}" \
FORCE_REBUILD="${FORCE_REBUILD:-0}" CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-0}" TAG="$TAG" \
  bash scripts/run_topo_darcy_brinkman_viz_0343.sh

summary="${RUN_ROOT}/diagonal_benchmark_0348a_summary.csv"
darcy_csv="${RUN_ROOT}/output/darcy_cost_0343.csv"
bench_csv="${RUN_ROOT}/output/${TOPO_BENCHMARK_FILENAME:-topo_benchmark_0348.csv}"
echo "tag,chiFile,darcyCsv,benchmarkCsv,darcyFinalLine,benchmarkFinalLine" > "$summary"
printf '%s,%s,%s,%s,"%s","%s"\n' \
  "$TAG" "$CHI_FILE" "$darcy_csv" "$bench_csv" \
  "$(tail -n 1 "$darcy_csv")" "$(tail -n 1 "$bench_csv")" >> "$summary"

echo "[0348a-benchmark] summary=$summary"
cat "$summary"
