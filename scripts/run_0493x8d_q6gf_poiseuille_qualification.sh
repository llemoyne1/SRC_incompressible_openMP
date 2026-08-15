#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

BASE="${BASE:-runs/0493x8d_q6gf_poiseuille_qualification}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"

echo "[0493x8d] Q6-g-f independent wall + Darcy/chi qualification"
echo "[0493x8d] root=$BASE preflight=$PREFLIGHT_ONLY"

BASE_RUN_ROOT="$BASE/solid" PREFLIGHT_ONLY="$PREFLIGHT_ONLY" \
LIVE_PROGRESS="$LIVE_PROGRESS" CLEAN_RUN_ROOT="$CLEAN_RUN_ROOT" \
bash scripts/run_0493x8d_q6gf_poiseuille_solid.sh

BASE_RUN_ROOT="$BASE/chi" PREFLIGHT_ONLY="$PREFLIGHT_ONLY" \
LIVE_PROGRESS="$LIVE_PROGRESS" CLEAN_RUN_ROOT="$CLEAN_RUN_ROOT" \
bash scripts/run_0493x8d_q6gf_poiseuille_chi.sh

if [[ "$PREFLIGHT_ONLY" == 0 ]]; then
  echo
  echo "[0493x8d] simulations complete"
  echo "[0493x8d] MATLAB:"
  echo "  addpath('matlab'); out = analyze_0493x8d_q6gf_poiseuille_qualification('$BASE');"
fi
