#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
export LIVE_PROGRESS

bash scripts/run_0491a_species_q6_cpu_reference.sh

if [[ "$PREFLIGHT_ONLY" == "1" ]]; then
  PREFLIGHT_ONLY=1 bash scripts/run_0493x4b_q6_force_fusion_tg.sh
  PREFLIGHT_ONLY=1 bash scripts/run_0493x5a_partial_liquid_free_surface.sh
  echo "[0493x5a-nonregression] preflight PASS"
  exit 0
fi

bash scripts/run_0493x4b_q6_force_fusion_tg.sh

BASE_RUN_ROOT=runs/0493x5a_full_liquid_fused_control_200x200_g10_s200 \
LIVE_VIS_ENABLE=0 LIVE_VIS_HOLD_ON_EXIT=0 STEPS=200 \
SUMMARY_EVERY=100 DUMP_STATE_EVERY=200 \
bash scripts/run_0493x4b_liquid_only_q6_force_fused.sh

BASE_RUN_ROOT=runs/0493x5a_partial_liquid_free_surface_200x200_g10_h0.5_s1000 \
LIVE_VIS_ENABLE=0 LIVE_VIS_HOLD_ON_EXIT=0 STEPS=1000 \
SUMMARY_EVERY=100 DUMP_STATE_EVERY=100 \
bash scripts/run_0493x5a_partial_liquid_free_surface.sh

echo "[0493x5a-nonregression] PASS"
