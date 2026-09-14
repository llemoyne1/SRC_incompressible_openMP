#!/usr/bin/env bash
# 0493x16l — direct post-stream impermeability qualification.
# Sequential by design: rigid/deformable x rest/boost, then stdlib Python analysis.
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT" || exit $?
BASE="${BASE_RUN_ROOT:-runs/0493x16l_chi_penetration_qualification}"
STEPS="${STEPS:-600}"

run_one() {
  local kind="$1" label="$2" ux="$3" deform="$4"
  echo "[0493x16l] kind=$kind frame=$label Ux=$ux deformable=$deform"
  BASE_RUN_ROOT="$BASE/$kind/$label" \
  CASE_LABEL="0493x16l_${kind}_${label}" \
  COMMON_UX="$ux" DEFORMABLE="$deform" STEPS="$STEPS" \
  SUMMARY_EVERY=1 CLEAN_RUN_ROOT=1 \
  bash scripts/run_0493x16j_chi_kinetic_specular_case.sh || exit $?
  local csv="$BASE/$kind/$label/fresh/output/chi_penetration_0493x16l.csv"
  [[ -s "$csv" ]] || { echo "[0493x16l] ERROR missing $csv" >&2; exit 2; }
  head -n 1 "$csv" | grep -q 'strictInsideParticles' || {
    echo "[0493x16l] ERROR malformed penetration CSV: $csv" >&2; exit 2; }
}

run_one rigid rest 0.0 0
run_one rigid boost "${BOOST_UX:-0.08}" 0
run_one deformable rest 0.0 1
run_one deformable boost "${BOOST_UX:-0.08}" 1

python3 scripts/analyze_0493x16l_chi_penetration.py "$BASE"
rc=$?
if (( rc == 0 )); then
  echo "[0493x16l] PASS root=$BASE"
else
  echo "[0493x16l] REVIEW root=$BASE analyzer_rc=$rc" >&2
fi
exit $rc
