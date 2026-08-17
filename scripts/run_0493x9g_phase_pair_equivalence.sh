#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

STEPS="${STEPS:-20}"
SIGMA="${SIGMA:-512}"
SEED="${SEED:-493904}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
BASE="${BASE_RUN_ROOT:-runs/0493x9g_phase_pair_equivalence}"
rm -rf "$BASE"
mkdir -p "$BASE"

run_one() {
  local mode="$1" a="$2" b="$3"
  echo "[0493x9g-suite] mode=$mode A=${a:-<default>} B=${b:-<default>}"
  BASE_RUN_ROOT="$BASE/$mode" \
  CLEAN_RUN_ROOT=1 \
  STEPS="$STEPS" SEED="$SEED" SIGMA="$SIGMA" \
  PHASE_A_SELECTOR="$a" PHASE_B_SELECTOR="$b" \
  LIVE_VIS_ENABLE="$LIVE_VIS_ENABLE" LIVE_VIS_HOLD_ON_EXIT=0 \
  LIVE_PROGRESS="$LIVE_PROGRESS" FILTERED_RECORDING_ENABLE=0 \
  bash scripts/run_0493x9f_ellipse_relaxation.sh
}

run_one legacy "" ""
run_one family "family:liquid" "family:gas"
run_one type "type:1" "type:2"

python3 scripts/analyze_0493x9g_phase_pair_equivalence.py --root "$BASE"
echo "[0493x9g-suite] PASS root=$BASE"
