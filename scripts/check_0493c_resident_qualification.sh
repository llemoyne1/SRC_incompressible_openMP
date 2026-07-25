#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
fail() { echo "[0493c-check] ERROR $*" >&2; exit 2; }

[[ -f README_0493B_UNIVERSAL_RESIDENT_PER_SPECIES.md ]] || fail "0493b base missing"
grep -q 'speciesKResamplingEnable' include/simulation_params.h || fail "0493b species switch missing"
grep -q 'resampDisabledSpeciesMutationCount' src/runtime_summary.cpp || fail "0493b scalar mutation counter missing"

for f in \
  scripts/run_0493b_universal_species_resampling_matrix.sh \
  scripts/run_0493c_species_resampling_qualification.sh \
  scripts/run_0493c_medium_qualification.sh \
  scripts/collect_0493c_validation_bundle.sh; do
  bash -n "$f" || fail "shell syntax: $f"
done
python3 -m py_compile scripts/analyze_0493c_resident_qualification.py || fail "Python syntax"

for f in \
  scripts/run_0493b_universal_species_resampling_matrix.sh \
  scripts/run_0493c_species_resampling_qualification.sh; do
  grep -q 'TARGET_CELL_MASS' "$f" || fail "mixture target mass missing: $f"
  grep -q 'resamplingPoorCellMassFraction' "$f" || fail "poor threshold override missing: $f"
  grep -q 'donor_cell = test_j\*nx + donor_i' "$f" || fail "interior donor cell missing: $f"
  grep -q 'GRID_SHIFT_ENABLE="${GRID_SHIFT_ENABLE:-false}"' "$f" || fail "deterministic grid-shift default missing: $f"
done

grep -q '09_periodic_colloid_only' scripts/run_0493c_species_resampling_qualification.sh || fail "reverse switch case missing"
grep -q '10_periodic_none' scripts/run_0493c_species_resampling_qualification.sh || fail "all-disabled base case missing"
grep -q '11_periodic_darcy_colloid_only' scripts/run_0493c_species_resampling_qualification.sh || fail "Darcy/chi colloid-only case missing"
grep -q '12_periodic_darcy_none' scripts/run_0493c_species_resampling_qualification.sh || fail "Darcy/chi all-disabled case missing"
grep -q '13_q6_segmented_solvent_only' scripts/run_0493c_species_resampling_qualification.sh || fail "Q6 disabled-species case missing"
grep -q '14_q6_segmented_darcy_solvent_only' scripts/run_0493c_species_resampling_qualification.sh || fail "combined Q6 + segmented + Darcy case missing"
grep -q 'darcyChiMode = circle' scripts/run_0493c_species_resampling_qualification.sh || fail "Darcy/chi circle field missing"
grep -q 'CUDA_RESAMPLING_CHI_FILTER_ENABLE=true' scripts/run_0493c_species_resampling_qualification.sh || fail "resampling chi filter missing"
if grep -Eq 'immersedSolid|immersed_circle|STATE_SOLID' scripts/run_0493c_species_resampling_qualification.sh; then
  fail "legacy immersed-solid qualification path still present"
fi

grep -q 'resampPopulationGuardApplied' scripts/analyze_0493c_resident_qualification.py || fail "resident guard activity audit missing"
grep -q 'require-direct-transfer' scripts/analyze_0493c_resident_qualification.py || fail "direct transfer audit missing"
grep -q 'directTransferOperations' scripts/analyze_0493c_resident_qualification.py || fail "direct transfer report missing"
grep -q '12_periodic_darcy_none' scripts/analyze_0493c_resident_qualification.py || fail "Darcy all-disabled audit exception missing"
grep -q 'cellMirrorDownloadBytes' scripts/analyze_0493c_resident_qualification.py || fail "resident policy audit missing"
grep -q 'compactPatchbackBytes' scripts/analyze_0493c_resident_qualification.py || fail "patchback audit missing"
grep -q 'disabledSpeciesMutationCount' scripts/analyze_0493c_resident_qualification.py || fail "disabled mutation audit missing"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
PREFLIGHT_ONLY=1 CLEAN_RUN_ROOT=1 RUN_ROOT="$tmp/base" \
  bash scripts/run_0493b_universal_species_resampling_matrix.sh > "$tmp/base_preflight.log"
[[ "$(grep -c ',PASS,preflight-only$' "$tmp/base/status_0493b.csv")" == 8 ]] || fail "base preflight is not 8/8"

PREFLIGHT_ONLY=1 CLEAN_RUN_ROOT=1 RUN_ROOT="$tmp/extended" CASE_GROUP=extended \
  bash scripts/run_0493c_species_resampling_qualification.sh > "$tmp/extended_preflight.log"
[[ "$(grep -c ',PASS,preflight-only$' "$tmp/extended/status_0493c.csv")" == 6 ]] || fail "extended preflight is not 6/6"
grep -q '^11_periodic_darcy_colloid_only,PASS,preflight-only$' "$tmp/extended/status_0493c.csv" || fail "Darcy colloid-only preflight missing"
grep -q '^12_periodic_darcy_none,PASS,preflight-only$' "$tmp/extended/status_0493c.csv" || fail "Darcy all-disabled preflight missing"
grep -q '^14_q6_segmented_darcy_solvent_only,PASS,preflight-only$' "$tmp/extended/status_0493c.csv" || fail "combined Q6/Darcy preflight missing"

PREFLIGHT_ONLY=1 CLEAN_RUN_ROOT=1 RUN_ROOT="$tmp/medium" CASE_GROUP=medium \
  bash scripts/run_0493c_species_resampling_qualification.sh > "$tmp/medium_preflight.log"
[[ "$(grep -c ',PASS,preflight-only$' "$tmp/medium/status_0493c.csv")" == 6 ]] || fail "medium preflight is not 6/6"
grep -q '^14_q6_segmented_darcy_solvent_only,PASS,preflight-only$' "$tmp/medium/status_0493c.csv" || fail "combined Q6/Darcy medium case missing"

git diff --check -- scripts README_0493C_RESIDENT_QUALIFICATION.md || fail "git diff --check"

echo "[0493c-check] PASS"
echo "[0493c-check] validation_only=1"
echo "[0493c-check] core_physics_changed=0"
echo "[0493c-check] base_preflight=8/8"
echo "[0493c-check] extended_preflight=6/6"
echo "[0493c-check] medium_preflight=6/6"
echo "[0493c-check] immersed_solid_scope=excluded"
echo "[0493c-check] darcy_chi_scope=reference"
echo "[0493c-check] direct_0490m_activity_required=1"
echo "[0493c-check] medium_runner=ready"
echo "[0493c-check] audit_collector=ready"
