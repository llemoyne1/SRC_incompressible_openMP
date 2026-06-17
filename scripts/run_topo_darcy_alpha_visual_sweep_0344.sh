#!/usr/bin/env bash
set -euo pipefail

# 0344/topo: visual sweep of Brinkman alphaMax on the SRC classic CUDA-VIZ path.
# Purpose: validate that the Darcy/Brinkman penalization is visible once thermal
# noise is reduced relative to the imposed mean flow.
#
# The script deliberately keeps Q6/resampling disabled through the underlying
# 0343 runner. It uses the persistent root livevis_control.kv by default.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ALPHAS="${ALPHAS:-0 20 80 320}"
TAG_PREFIX="${TAG_PREFIX:-topo_darcy_alpha_sweep_0344}"

# Low-noise visualization defaults: the original 0343 defaults (kBT=5, gamma=20,
# U0=0.05, 600x320 live grid) are useful for stability but make ux/speed visually
# noise-dominated. These defaults make the effect of alpha easier to see.
export LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
export LIVE_VIS_CONTROL_FILE="${LIVE_VIS_CONTROL_FILE:-livevis_control.kv}"
export LIVE_VIS_CONTROL_RESET="${LIVE_VIS_CONTROL_RESET:-0}"
export LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-ux}"
export LIVE_VIS_NX="${LIVE_VIS_NX:-360}"
export LIVE_VIS_NY="${LIVE_VIS_NY:-96}"
export LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-5}"
export LIVE_VIS_CLIP="${LIVE_VIS_CLIP:-0.5}"
export LIVE_VIS_GAIN="${LIVE_VIS_GAIN:-1.0}"
export LIVE_VIS_SMOOTH_PASSES="${LIVE_VIS_SMOOTH_PASSES:-3}"
export LIVE_VIS_COLORMAP="${LIVE_VIS_COLORMAP:-thermal}"

export GAMMA="${GAMMA:-40}"
export KBT="${KBT:-0.1}"
export U0="${U0:-0.5}"
export STEPS="${STEPS:-2000}"
export DARCY_COST_EVERY="${DARCY_COST_EVERY:-20}"
export FORCE_REBUILD="${FORCE_REBUILD:-0}"
export AUTO_BUILD="${AUTO_BUILD:-1}"
export CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"

mkdir -p "runs/${TAG_PREFIX}/logs"
summary="runs/${TAG_PREFIX}/alpha_sweep_0344_summary.csv"
echo "alphaMax,tag,csv,finalLine" > "$summary"

for alpha in $ALPHAS; do
  safe_alpha="${alpha//./p}"
  tag="${TAG_PREFIX}_a${safe_alpha}"
  echo "[0344-alpha-sweep] running alphaMax=$alpha tag=$tag"
  DARCY_ALPHA_MAX="$alpha" TAG="$tag" bash scripts/run_topo_darcy_brinkman_viz_0343.sh
  csv="runs/${tag}/output/darcy_cost_0343.csv"
  if [[ -f "$csv" ]]; then
    final_line="$(tail -n 1 "$csv")"
    printf '%s,%s,%s,"%s"\n' "$alpha" "$tag" "$csv" "$final_line" >> "$summary"
  else
    printf '%s,%s,%s,"MISSING"\n' "$alpha" "$tag" "$csv" >> "$summary"
  fi
  echo "[0344-alpha-sweep] done alphaMax=$alpha"
done

echo "[0344-alpha-sweep] summary=$summary"
