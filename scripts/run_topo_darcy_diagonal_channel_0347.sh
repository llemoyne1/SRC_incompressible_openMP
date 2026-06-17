#!/usr/bin/env bash
set -euo pipefail

# 0347/topo: diagonal channel chi-file case inspired by the provided RANS reference.
# Scope: CUDA-VIZ SRC classic + pure Brinkman.  Geometry validation and first
# observable extraction on a simple inlet-left / outlet-bottom diagonal conduit.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

Lx="${Lx:-1.0}"; Ly="${Ly:-1.0}"; NX="${NX:-256}"; NY="${NY:-256}"
TAG="${TAG:-topo_darcy_diagonal_channel_0347}"
RUN_ROOT="runs/${TAG}"
CHI_DIR="${CHI_DIR:-${RUN_ROOT}/chi}"
CHI_FILE="${CHI_FILE:-${CHI_DIR}/diagonal_channel_${NX}x${NY}.f32}"

INLET_Y="${INLET_Y:-0.78}"
OUTLET_X="${OUTLET_X:-0.82}"
PIPE_WIDTH="${PIPE_WIDTH:-0.14}"
DARCY_INTERFACE_WIDTH="${DARCY_INTERFACE_WIDTH:-0.015}"

mkdir -p "$CHI_DIR" "${RUN_ROOT}/logs"
python3 scripts/generate_topo_chi_field_0345.py \
  --mode diagonal_channel --out "$CHI_FILE" \
  --Nx "$NX" --Ny "$NY" --Lx "$Lx" --Ly "$Ly" \
  --inlet-y "$INLET_Y" --outlet-x "$OUTLET_X" \
  --pipe-width "$PIPE_WIDTH" --interface-width "$DARCY_INTERFACE_WIDTH" \
  | tee "${RUN_ROOT}/logs/generate_diagonal_channel_0347.log"

BIN="${BIN:-build/src_mpcd_base_cuda_topo_0345}" \
Lx="$Lx" Ly="$Ly" NX="$NX" NY="$NY" \
DARCY_CHI_MODE=file DARCY_CHI_FILE="$CHI_FILE" DARCY_CHI_FILE_FORMAT=float32 \
DARCY_ALPHA_MAX="${DARCY_ALPHA_MAX:-320}" DARCY_Q="${DARCY_Q:-0.1}" DARCY_COST_EVERY="${DARCY_COST_EVERY:-20}" \
GAMMA="${GAMMA:-40}" KBT="${KBT:-0.1}" U0="${U0:-0.5}" STEPS="${STEPS:-3000}" \
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}" LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-chi}" LIVE_VIS_CLIP="${LIVE_VIS_CLIP:-1}" \
LIVE_VIS_NX="${LIVE_VIS_NX:-$NX}" LIVE_VIS_NY="${LIVE_VIS_NY:-$NY}" LIVE_VIS_SMOOTH_PASSES="${LIVE_VIS_SMOOTH_PASSES:-2}" \
FORCE_REBUILD="${FORCE_REBUILD:-0}" CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-0}" TAG="$TAG" \
  bash scripts/run_topo_darcy_brinkman_viz_0343.sh

summary="${RUN_ROOT}/diagonal_channel_0347_summary.csv"
csv="${RUN_ROOT}/output/darcy_cost_0343.csv"
echo "tag,chiFile,inletY,outletX,pipeWidth,csv,finalLine" > "$summary"
printf '%s,%s,%s,%s,%s,%s,"%s"\n' "$TAG" "$CHI_FILE" "$INLET_Y" "$OUTLET_X" "$PIPE_WIDTH" "$csv" "$(tail -n 1 "$csv")" >> "$summary"

echo "[0347-diagonal] summary=$summary"
cat "$summary"
