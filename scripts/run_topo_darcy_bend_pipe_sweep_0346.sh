#!/usr/bin/env bash
set -euo pipefail

# 0346/topo: sweep first bend-pipe geometry parameters using external chi_file.
# Default sweep varies pipe width at fixed bend radius.  It is intended to test
# observables and visualization consistency before a true inlet/outlet benchmark.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

Lx="${Lx:-1.5}"; Ly="${Ly:-0.4}"; NX="${NX:-360}"; NY="${NY:-96}"
WIDTHS="${WIDTHS:-0.06 0.08 0.10 0.12 0.15}"
TAG_PREFIX="${TAG_PREFIX:-topo_darcy_bend_pipe_sweep_0346}"
RUN_ROOT="runs/${TAG_PREFIX}"
CHI_DIR="${RUN_ROOT}/chi"
mkdir -p "$CHI_DIR" "${RUN_ROOT}/logs"
summary="${RUN_ROOT}/bend_pipe_sweep_0346_summary.csv"
echo "pipeWidth,bendRadius,chiFile,csv,finalLine" > "$summary"

for w in $WIDTHS; do
  safe_w="${w//./p}"
  chi_file="${CHI_DIR}/bend_pipe_w${safe_w}_${NX}x${NY}.f32"
  python3 scripts/generate_topo_chi_field_0345.py \
    --mode bend_pipe --out "$chi_file" \
    --Nx "$NX" --Ny "$NY" --Lx "$Lx" --Ly "$Ly" \
    --cx "${BEND_CX:-0.45}" --cy "${BEND_CY:-0.10}" \
    --bend-radius "${BEND_RADIUS:-0.18}" --pipe-width "$w" --interface-width "${DARCY_INTERFACE_WIDTH:-0.01}" \
    | tee "${RUN_ROOT}/logs/generate_w${safe_w}.log"
  tag="${TAG_PREFIX}_w${safe_w}"
  echo "[0346-bend-pipe-sweep] running width=$w tag=$tag"
  BIN="${BIN:-build/src_mpcd_base_cuda_topo_0345}" \
  Lx="$Lx" Ly="$Ly" NX="$NX" NY="$NY" \
  DARCY_CHI_MODE=file DARCY_CHI_FILE="$chi_file" DARCY_CHI_FILE_FORMAT=float32 \
  DARCY_ALPHA_MAX="${DARCY_ALPHA_MAX:-320}" DARCY_Q="${DARCY_Q:-0.1}" DARCY_COST_EVERY="${DARCY_COST_EVERY:-20}" \
  GAMMA="${GAMMA:-40}" KBT="${KBT:-0.1}" U0="${U0:-0.5}" STEPS="${STEPS:-1200}" \
  LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-0}" FORCE_REBUILD="${FORCE_REBUILD:-0}" CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}" TAG="$tag" \
    bash scripts/run_topo_darcy_brinkman_viz_0343.sh
  csv="runs/${tag}/output/darcy_cost_0343.csv"
  printf '%s,%s,%s,%s,"%s"\n' "$w" "${BEND_RADIUS:-0.18}" "$chi_file" "$csv" "$(tail -n 1 "$csv")" >> "$summary"
done

echo "[0346-bend-pipe-sweep] summary=$summary"
cat "$summary"
