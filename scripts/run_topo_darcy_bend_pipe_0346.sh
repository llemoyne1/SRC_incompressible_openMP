#!/usr/bin/env bash
set -euo pipefail

# 0346/topo: first bend-pipe validation using external chi_file.
# Scope: CUDA-VIZ SRC classic + pure Brinkman.  This is a geometry/topology
# validation case, not yet an inlet/outlet pressure-drop benchmark.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

Lx="${Lx:-1.5}"; Ly="${Ly:-0.4}"; NX="${NX:-360}"; NY="${NY:-96}"
TAG="${TAG:-topo_darcy_bend_pipe_0346}"
RUN_ROOT="runs/${TAG}"
CHI_DIR="${CHI_DIR:-${RUN_ROOT}/chi}"
CHI_FILE="${CHI_FILE:-${CHI_DIR}/bend_pipe_${NX}x${NY}.f32}"

BEND_CX="${BEND_CX:-0.45}"
BEND_CY="${BEND_CY:-0.10}"
BEND_RADIUS="${BEND_RADIUS:-0.18}"
PIPE_WIDTH="${PIPE_WIDTH:-0.10}"
DARCY_INTERFACE_WIDTH="${DARCY_INTERFACE_WIDTH:-0.01}"

mkdir -p "$CHI_DIR" "${RUN_ROOT}/logs"
python3 scripts/generate_topo_chi_field_0345.py \
  --mode bend_pipe --out "$CHI_FILE" \
  --Nx "$NX" --Ny "$NY" --Lx "$Lx" --Ly "$Ly" \
  --cx "$BEND_CX" --cy "$BEND_CY" \
  --bend-radius "$BEND_RADIUS" --pipe-width "$PIPE_WIDTH" --interface-width "$DARCY_INTERFACE_WIDTH" \
  | tee "${RUN_ROOT}/logs/generate_bend_pipe_0346.log"

# Defaults chosen to make penalization visible without excessive runtime.
BIN="${BIN:-build/src_mpcd_base_cuda_topo_0345}" \
Lx="$Lx" Ly="$Ly" NX="$NX" NY="$NY" \
DARCY_CHI_MODE=file DARCY_CHI_FILE="$CHI_FILE" DARCY_CHI_FILE_FORMAT=float32 \
DARCY_ALPHA_MAX="${DARCY_ALPHA_MAX:-320}" DARCY_Q="${DARCY_Q:-0.1}" DARCY_COST_EVERY="${DARCY_COST_EVERY:-20}" \
GAMMA="${GAMMA:-40}" KBT="${KBT:-0.1}" U0="${U0:-0.5}" STEPS="${STEPS:-3000}" \
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}" LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-chi}" LIVE_VIS_CLIP="${LIVE_VIS_CLIP:-1}" \
LIVE_VIS_NX="${LIVE_VIS_NX:-$NX}" LIVE_VIS_NY="${LIVE_VIS_NY:-$NY}" LIVE_VIS_SMOOTH_PASSES="${LIVE_VIS_SMOOTH_PASSES:-2}" \
FORCE_REBUILD="${FORCE_REBUILD:-0}" CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-0}" TAG="$TAG" \
  bash scripts/run_topo_darcy_brinkman_viz_0343.sh

summary="${RUN_ROOT}/bend_pipe_0346_summary.csv"
csv="${RUN_ROOT}/output/darcy_cost_0343.csv"
echo "tag,chiFile,csv,finalLine" > "$summary"
printf '%s,%s,%s,"%s"\n' "$TAG" "$CHI_FILE" "$csv" "$(tail -n 1 "$csv")" >> "$summary"

echo "[0346-bend-pipe] summary=$summary"
cat "$summary"
