#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"; cd "$ROOT"
CAMPAIGN_ROOT="${CAMPAIGN_ROOT:-runs/0493x17d_article_solids_smoke}"
BASE_RUN_ROOT="$CAMPAIGN_ROOT/fixed_membrane" STEPS=80 MEMBRANE_OUTPUT_EVERY=5 RECORD_ENABLE=false FILTERED_RECORDING_ENABLE=0 LIVE_PROGRESS="${LIVE_PROGRESS:-1}" bash scripts/run_0493x17d_fixed_membrane_case.sh
BASE_RUN_ROOT="$CAMPAIGN_ROOT/pressure_piston" STEPS=80 RECORD_ENABLE=false FILTERED_RECORDING_ENABLE=0 LIVE_PROGRESS="${LIVE_PROGRESS:-1}" bash scripts/run_0493x17d_pressure_piston_case.sh
python3 scripts/analyze_0493x17d_article_solids.py --root "$CAMPAIGN_ROOT" || true
