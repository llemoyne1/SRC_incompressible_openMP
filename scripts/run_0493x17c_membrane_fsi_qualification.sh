#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

CAMPAIGN_ROOT="${CAMPAIGN_ROOT:-runs/0493x17c_membrane_fsi_qualification}"
STEPS="${STEPS:-800}"
NX="${NX:-192}"
NY="${NY:-128}"
GAMMA="${GAMMA:-20}"
DT="${DT:-0.002}"
RELATIVE_UX="${RELATIVE_UX:-0.08}"
COMMON_BOOST_UX="${COMMON_BOOST_UX:-0.08}"
SEED="${SEED:-4931703}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"

rm -rf "$CAMPAIGN_ROOT"
mkdir -p "$CAMPAIGN_ROOT/analysis"

run_frame() {
  local frame=$1 boost=$2
  echo
  echo "===== 0493x17c qualification frame=$frame boost=$boost ====="
  FRAME_LABEL="$frame" \
  BASE_RUN_ROOT="$CAMPAIGN_ROOT/$frame" \
  CASE_LABEL="0493x17c_membrane_${frame}" \
  BOOST_UX="$boost" RELATIVE_UX="$RELATIVE_UX" \
  STEPS="$STEPS" NX="$NX" NY="$NY" GAMMA="$GAMMA" DT="$DT" SEED="$SEED" \
  SUMMARY_EVERY=1 MEMBRANE_OUTPUT_EVERY="${MEMBRANE_OUTPUT_EVERY:-40}" \
  LIVE_VIS_ENABLE="$LIVE_VIS_ENABLE" LIVE_PROGRESS="$LIVE_PROGRESS" \
  CLEAN_RUN_ROOT=1 \
  bash scripts/run_0493x17c_membrane_fsi_case.sh
}

run_frame rest 0.0
run_frame boost "$COMMON_BOOST_UX"

set +e
python3 scripts/analyze_0493x17c_membrane_fsi.py --root "$CAMPAIGN_ROOT"
rc=$?
set -e

echo "[0493x17c] summary=$CAMPAIGN_ROOT/analysis/summary_0493x17c.txt"
cat "$CAMPAIGN_ROOT/analysis/summary_0493x17c.txt"
exit "$rc"
