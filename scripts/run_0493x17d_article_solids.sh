#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"; cd "$ROOT"
CAMPAIGN_ROOT="${CAMPAIGN_ROOT:-runs/0493x17d_article_solids}"; STEPS_MEMBRANE="${STEPS_MEMBRANE:-600}"; STEPS_PISTON="${STEPS_PISTON:-500}"
BASE_RUN_ROOT="$CAMPAIGN_ROOT/fixed_membrane" STEPS="$STEPS_MEMBRANE" LIVE_PROGRESS="${LIVE_PROGRESS:-1}" bash scripts/run_0493x17d_fixed_membrane_case.sh
BASE_RUN_ROOT="$CAMPAIGN_ROOT/pressure_piston" STEPS="$STEPS_PISTON" LIVE_PROGRESS="${LIVE_PROGRESS:-1}" bash scripts/run_0493x17d_pressure_piston_case.sh
python3 scripts/analyze_0493x17d_article_solids.py --root "$CAMPAIGN_ROOT"
