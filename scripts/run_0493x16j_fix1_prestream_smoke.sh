#!/usr/bin/env bash
# 0493x16j-fix1 — short discriminating validation.
# 1) fixed chi wall at rest: impermeability without outward_bath/chiVP/Darcy force.
# 2) rigid material wall rest vs common Galilean boost.
# Sequential by design; these are short/small runs, so LiveVis is off by default.

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT" || exit $?

BASE="${BASE_RUN_ROOT:-runs/0493x16j_fix1_prestream_smoke}"
STATIC_STEPS="${STATIC_STEPS:-200}"
GALILEAN_STEPS="${GALILEAN_STEPS:-400}"
BOOST_UX="${BOOST_UX:-0.08}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-0}"

run_case() {
  local label="$1" ux="$2" dynamics="$3" steps="$4"
  echo "[0493x16j-fix1-smoke] case=$label Ux=$ux dynamics=$dynamics steps=$steps"
  BASE_RUN_ROOT="$BASE/$label" \
  CASE_LABEL="0493x16j_fix1_${label}" \
  COMMON_UX="$ux" \
  CHI_SOLID_DYNAMICS_ENABLE="$dynamics" \
  DEFORMABLE=0 \
  STEPS="$steps" \
  SUMMARY_EVERY=1 \
  DUMP_STATE_EVERY=0 \
  LIVE_VIS_ENABLE="$LIVE_VIS_ENABLE" \
  CLEAN_RUN_ROOT=1 \
  bash scripts/run_0493x16j_chi_kinetic_specular_case.sh || exit $?
}

run_case static_rest 0.0 0 "$STATIC_STEPS"
run_case rigid_rest 0.0 1 "$GALILEAN_STEPS"
run_case rigid_boost "$BOOST_UX" 1 "$GALILEAN_STEPS"

echo "[0493x16j-fix1-smoke] COMPLETE root=$BASE"
