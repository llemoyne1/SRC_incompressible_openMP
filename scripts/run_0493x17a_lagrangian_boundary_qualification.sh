#!/usr/bin/env bash
# Full first-jalon qualification: fixed curved, rigid mobile and prescribed deformable,
# each in rest and common Galilean boost frames.
set -u
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT" || exit $?
BASE="${BASE_RUN_ROOT:-runs/0493x17a_lagrangian_boundary_qualification}"
STATIC_STEPS="${STATIC_STEPS:-800}"
FULL_STEPS="${FULL_STEPS:-600}"
BOOST_UX="${BOOST_UX:-0.08}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
rm -rf "$BASE"; mkdir -p "$BASE"
bash scripts/check_0493x17a_lagrangian_boundary.sh || exit $?
run_case(){
  local root="$1" label="$2" ux="$3" deform="$4" static_curve="$5" steps="$6"
  echo "[0493x17a] run label=$label Ux=$ux deform=$deform staticCurve=$static_curve steps=$steps"
  if [[ "$static_curve" == 1 ]]; then
    SRC_X16I_STATIC_CURVED_0493X16M=1 \
    BASE_RUN_ROOT="$root" CASE_LABEL="$label" COMMON_UX="$ux" DEFORMABLE="$deform" \
    STEPS="$steps" SUMMARY_EVERY=1 DUMP_STATE_EVERY=0 CLEAN_RUN_ROOT=1 \
    LIVE_VIS_ENABLE="$LIVE_VIS_ENABLE" FILTERED_RECORDING_ENABLE=0 RECORD_ENABLE=false \
    bash scripts/run_0493x17a_lagrangian_boundary_case.sh
  else
    BASE_RUN_ROOT="$root" CASE_LABEL="$label" COMMON_UX="$ux" DEFORMABLE="$deform" \
    STEPS="$steps" SUMMARY_EVERY=1 DUMP_STATE_EVERY=0 CLEAN_RUN_ROOT=1 \
    LIVE_VIS_ENABLE="$LIVE_VIS_ENABLE" FILTERED_RECORDING_ENABLE=0 RECORD_ENABLE=false \
    bash scripts/run_0493x17a_lagrangian_boundary_case.sh
  fi
}
run_case "$BASE/static_curved/rest" 0493x17a_static_rest 0.0 1 1 "$STATIC_STEPS" || exit $?
run_case "$BASE/static_curved/boost" 0493x17a_static_boost "$BOOST_UX" 1 1 "$STATIC_STEPS" || exit $?
run_case "$BASE/full_mobile/rigid/rest" 0493x17a_rigid_rest 0.0 0 0 "$FULL_STEPS" || exit $?
run_case "$BASE/full_mobile/rigid/boost" 0493x17a_rigid_boost "$BOOST_UX" 0 0 "$FULL_STEPS" || exit $?
run_case "$BASE/full_mobile/deform/rest" 0493x17a_deform_rest 0.0 1 0 "$FULL_STEPS" || exit $?
run_case "$BASE/full_mobile/deform/boost" 0493x17a_deform_boost "$BOOST_UX" 1 0 "$FULL_STEPS" || exit $?
python3 scripts/analyze_0493x17a_lagrangian_boundary_qualification.py "$BASE"
