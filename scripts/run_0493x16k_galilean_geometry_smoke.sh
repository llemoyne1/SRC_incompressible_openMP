#!/usr/bin/env bash
# 0493x16k short, sequential Galilean geometry test.
# Four 4-step cases are enough to expose the x16j grid-phase defect: step 2
# starts from positions produced by the first wall transport, before later
# long-time statistical divergence can obscure the geometry signal.
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT" || exit $?
BASE="${BASE_RUN_ROOT:-runs/0493x16k_galilean_geometry_smoke}"
STEPS="${STEPS:-4}"
BOOST_UX="${BOOST_UX:-0.08}"

run_one() {
  local kind="$1" frame="$2" ux="$3" deform="$4"
  echo "[0493x16k-smoke] kind=$kind frame=$frame Ux=$ux deformable=$deform"
  BASE_RUN_ROOT="$BASE/$kind/$frame" \
  CASE_LABEL="0493x16k_${kind}_${frame}" \
  COMMON_UX="$ux" DEFORMABLE="$deform" STEPS="$STEPS" \
  SUMMARY_EVERY=1 CLEAN_RUN_ROOT=1 \
  LIVE_VIS_ENABLE=0 FILTERED_RECORDING_ENABLE=0 RECORD_ENABLE=false \
  bash scripts/run_0493x16j_chi_kinetic_specular_case.sh || exit $?
}

run_one rigid rest 0.0 0
run_one rigid boost "$BOOST_UX" 0
run_one deformable rest 0.0 1
run_one deformable boost "$BOOST_UX" 1

python3 scripts/analyze_0493x16k_galilean_geometry_smoke.py "$BASE" "$BOOST_UX" || exit $?
echo "[0493x16k-smoke] COMPLETE root=$BASE"
