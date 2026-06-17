#!/usr/bin/env bash
set -euo pipefail

# 0345/topo: validate darcyChiMode=file against the analytic circle mode.
# The two runs use the same state generator seed and physical parameters; only
# the chi source changes.  Expected result: close meanChi/meanAlpha/leak/power,
# within stochastic fluctuations.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

Lx="${Lx:-1.5}"; Ly="${Ly:-0.4}"; NX="${NX:-360}"; NY="${NY:-96}"
DARCY_CX="${DARCY_CX:-0.45}"; DARCY_CY="${DARCY_CY:-0.20}"; DARCY_R="${DARCY_R:-0.055}"; DARCY_INTERFACE_WIDTH="${DARCY_INTERFACE_WIDTH:-0.01}"
TAG_PREFIX="${TAG_PREFIX:-topo_darcy_chi_file_circle_validation_0345}"
CHI_DIR="runs/${TAG_PREFIX}/chi"
CHI_FILE="${CHI_FILE:-${CHI_DIR}/circle_R${DARCY_R}_${NX}x${NY}.f32}"

mkdir -p "$CHI_DIR" "runs/${TAG_PREFIX}/logs"
python3 scripts/generate_topo_chi_field_0345.py \
  --mode circle_obstacle --out "$CHI_FILE" \
  --Nx "$NX" --Ny "$NY" --Lx "$Lx" --Ly "$Ly" \
  --cx "$DARCY_CX" --cy "$DARCY_CY" --radius "$DARCY_R" --interface-width "$DARCY_INTERFACE_WIDTH" \
  | tee "runs/${TAG_PREFIX}/logs/generate_chi.log"

COMMON_ENV=(
  Lx="$Lx" Ly="$Ly" NX="$NX" NY="$NY"
  DARCY_CX="$DARCY_CX" DARCY_CY="$DARCY_CY" DARCY_R="$DARCY_R" DARCY_INTERFACE_WIDTH="$DARCY_INTERFACE_WIDTH"
  GAMMA="${GAMMA:-40}" KBT="${KBT:-0.1}" U0="${U0:-0.5}" STEPS="${STEPS:-600}"
  DARCY_ALPHA_MAX="${DARCY_ALPHA_MAX:-80}" DARCY_Q="${DARCY_Q:-0.1}" DARCY_COST_EVERY="${DARCY_COST_EVERY:-20}"
  LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-0}" FORCE_REBUILD="${FORCE_REBUILD:-0}" CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"
)

env "${COMMON_ENV[@]}" DARCY_CHI_MODE=circle TAG="${TAG_PREFIX}_analytic" \
  bash scripts/run_topo_darcy_brinkman_viz_0343.sh

env "${COMMON_ENV[@]}" DARCY_CHI_MODE=file DARCY_CHI_FILE="$CHI_FILE" DARCY_CHI_FILE_FORMAT=float32 TAG="${TAG_PREFIX}_file" \
  bash scripts/run_topo_darcy_brinkman_viz_0343.sh

summary="runs/${TAG_PREFIX}/chi_file_circle_validation_0345_summary.csv"
echo "mode,csv,finalLine" > "$summary"
for mode in analytic file; do
  csv="runs/${TAG_PREFIX}_${mode}/output/darcy_cost_0343.csv"
  printf '%s,%s,"%s"\n' "$mode" "$csv" "$(tail -n 1 "$csv")" >> "$summary"
done

echo "[0345-chi-validation] summary=$summary"
cat "$summary"
