#!/usr/bin/env bash

# 0493x16i — compare two CUDA-resident representations of a prescribed
# deformable strictly-impermeable wall, without changing the historical
# porous-Darcy constitutive path:
#   binary_event   : historical binary chi + remap only when a cell center
#                    changes fluid -> solid;
#   swept_geometry : same historical binary Darcy interior, but continuous
#                    exact-interface exclusion/remap in cut/swept geometry.
#
# Each representation is run in two Galilean frames with the same RNG seed:
#   rest  : common translation U_G = 0
#   boost : common translation U_G = BOOST_UX
# The wall deformation relative to its translating center is identical in the
# two frames.  Four runs are therefore produced for a direct comparison.

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT" || exit $?

BOOST_UX="${BOOST_UX:-0.08}"
STEPS="${STEPS:-1600}"
DEFORM_AMPLITUDE_CELLS="${DEFORM_AMPLITUDE_CELLS:-0.75}"
DEFORM_PERIOD_STEPS="${DEFORM_PERIOD_STEPS:-400}"
SEED="${SEED:-4931601}"
BASE="${BASE_RUN_ROOT:-runs/0493x16i_deformable_impermeable_compare}"
CLEAN_COMPARE_ROOT="${CLEAN_COMPARE_ROOT:-1}"

if [[ "$CLEAN_COMPARE_ROOT" != "0" ]]; then
  rm -rf "$BASE"
fi
mkdir -p "$BASE"

cat > "$BASE/compare_meta_0493x16i.txt" <<META
experiment=0493x16i_deformable_impermeable_compare
priority=strict_impermeable_deformable_solid
porousDarcyPolicy=historical_path_unchanged
boostCommonUx=$BOOST_UX
steps=$STEPS
deformAmplitudeCells=$DEFORM_AMPLITUDE_CELLS
deformPeriodSteps=$DEFORM_PERIOD_STEPS
seed=$SEED
modeA=binary_event
modeB=swept_geometry
META

run_one() {
  local mode="$1"
  local frame="$2"
  local ux="$3"
  local root="$BASE/$mode/$frame"
  local label="0493x16i_${mode}_${frame}"
  printf '\n===== x16i %s / %s / commonUx=%s =====\n' "$mode" "$frame" "$ux"
  BASE_RUN_ROOT="$root" \
  CASE_LABEL="$label" \
  EXCLUSION_MODE="$mode" \
  COMMON_UX="$ux" \
  STEPS="$STEPS" \
  SEED="$SEED" \
  DEFORM_AMPLITUDE_CELLS="$DEFORM_AMPLITUDE_CELLS" \
  DEFORM_PERIOD_STEPS="$DEFORM_PERIOD_STEPS" \
  CLEAN_RUN_ROOT=1 \
  LIVE_PROGRESS="${LIVE_PROGRESS:-1}" \
  LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}" \
  LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-1}" \
  LIVE_VIS_HOLD_ON_EXIT=0 \
  FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-1}" \
  RECORD_ENABLE="${RECORD_ENABLE:-true}" \
  RECORD_EVERY="${RECORD_EVERY:-50}" \
  ALLOW_LARGE_DUMPS="${ALLOW_LARGE_DUMPS:-1}" \
  bash scripts/run_0493x16i_deformable_impermeable_case.sh || return $?
}

# One dependent operation at a time, deliberately sequential.
run_one binary_event rest 0.0 || exit $?
run_one binary_event boost "$BOOST_UX" || exit $?
run_one swept_geometry rest 0.0 || exit $?
run_one swept_geometry boost "$BOOST_UX" || exit $?

echo "[0493x16i] comparison COMPLETE root=$BASE"
echo "[0493x16i] MATLAB: analyze_0493x16i_deformable_impermeable_compare('../$BASE')"
