#!/usr/bin/env bash
set -euo pipefail

# 0345/topo: radius sweep using external chi files.  This tests the topology
# input path expected by an external optimizer while avoiding analytic geometry
# inside the solver step.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

Lx="${Lx:-1.5}"; Ly="${Ly:-0.4}"; NX="${NX:-360}"; NY="${NY:-96}"
RADII="${RADII:-0.02 0.04 0.055 0.08 0.11}"
TAG_PREFIX="${TAG_PREFIX:-topo_darcy_radius_sweep_0345}"
CHI_DIR="runs/${TAG_PREFIX}/chi"
mkdir -p "$CHI_DIR" "runs/${TAG_PREFIX}/logs"
summary="runs/${TAG_PREFIX}/radius_sweep_0345_summary.csv"
echo "radius,chiFile,csv,finalLine" > "$summary"

for r in $RADII; do
  safe_r="${r//./p}"
  chi_file="${CHI_DIR}/circle_R${safe_r}_${NX}x${NY}.f32"
  python3 scripts/generate_topo_chi_field_0345.py \
    --mode circle_obstacle --out "$chi_file" \
    --Nx "$NX" --Ny "$NY" --Lx "$Lx" --Ly "$Ly" \
    --cx "${DARCY_CX:-0.45}" --cy "${DARCY_CY:-0.20}" --radius "$r" --interface-width "${DARCY_INTERFACE_WIDTH:-0.01}" \
    | tee "runs/${TAG_PREFIX}/logs/generate_R${safe_r}.log"
  tag="${TAG_PREFIX}_R${safe_r}"
  echo "[0345-radius-sweep] running radius=$r tag=$tag"
  Lx="$Lx" Ly="$Ly" NX="$NX" NY="$NY" \
  DARCY_CHI_MODE=file DARCY_CHI_FILE="$chi_file" DARCY_CHI_FILE_FORMAT=float32 \
  DARCY_ALPHA_MAX="${DARCY_ALPHA_MAX:-80}" DARCY_Q="${DARCY_Q:-0.1}" DARCY_COST_EVERY="${DARCY_COST_EVERY:-20}" \
  GAMMA="${GAMMA:-40}" KBT="${KBT:-0.1}" U0="${U0:-0.5}" STEPS="${STEPS:-1000}" \
  LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-0}" FORCE_REBUILD="${FORCE_REBUILD:-0}" CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}" \
  TAG="$tag" bash scripts/run_topo_darcy_brinkman_viz_0343.sh
  csv="runs/${tag}/output/darcy_cost_0343.csv"
  printf '%s,%s,%s,"%s"\n' "$r" "$chi_file" "$csv" "$(tail -n 1 "$csv")" >> "$summary"
done

echo "[0345-radius-sweep] summary=$summary"
cat "$summary"
