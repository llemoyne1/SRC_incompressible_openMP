#!/usr/bin/env bash
# Four paired cases: rigid/deformable x rest/boost. Sequential by design.
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT" || exit $?
BASE="${BASE_RUN_ROOT:-runs/0493x16j_chi_kinetic_specular_compare}"
STEPS="${STEPS:-1200}"

run_one() {
  local kind="$1" label="$2" ux="$3" deform="$4"
  echo "[0493x16j-compare] kind=$kind frame=$label Ux=$ux deformable=$deform"
  BASE_RUN_ROOT="$BASE/$kind/$label" \
  CASE_LABEL="0493x16j_${kind}_${label}" \
  COMMON_UX="$ux" DEFORMABLE="$deform" STEPS="$STEPS" \
  CLEAN_RUN_ROOT=1 \
  bash scripts/run_0493x16j_chi_kinetic_specular_case.sh || exit $?
}

run_one rigid rest 0.0 0
run_one rigid boost "${BOOST_UX:-0.08}" 0
run_one deformable rest 0.0 1
run_one deformable boost "${BOOST_UX:-0.08}" 1

echo "[0493x16j-compare] COMPLETE root=$BASE"
