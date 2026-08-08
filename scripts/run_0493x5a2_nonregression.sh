#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

python3 scripts/check_0493x5a2_generator_profiles.py --root "$ROOT"

LIVE_PROGRESS="${LIVE_PROGRESS:-1}" PREFLIGHT_ONLY=1 \
BASE_RUN_ROOT="${BASE_RUN_ROOT:-runs/0493x5a2_nonregression_preflight}" \
bash scripts/run_0493x5a2_dynamic_free_surface_dam_break.sh

if [[ "${RUN_SMOKE:-0}" == "1" ]]; then
  LIVE_PROGRESS="${LIVE_PROGRESS:-1}" \
  BASE_RUN_ROOT="${SMOKE_RUN_ROOT:-runs/0493x5a2_nonregression_smoke_s20}" \
  LIVE_VIS_ENABLE=0 LIVE_VIS_HOLD_ON_EXIT=0 \
  STEPS=20 SUMMARY_EVERY=1 DUMP_STATE_EVERY=10 \
  bash scripts/run_0493x5a2_dynamic_free_surface_dam_break.sh
fi

echo "[0493x5a2-nonregression] PASS smoke=${RUN_SMOKE:-0}"
