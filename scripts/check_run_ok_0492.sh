#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

expected_bin='build/src_mpcd_base_cuda_q6_resident_livevis_0486'
for f in scripts/run_ok*.sh scripts/src_mpcd_run_common_0434.sh; do
  bash -n "$f"
done
python3 -m py_compile scripts/check_injection_species_0492b.py

for f in scripts/run_ok*.sh; do
  grep -Fq "$expected_bin" "$f" || { echo "[0492b-check] missing default 0486 binary: $f" >&2; exit 1; }
  grep -Fq 'LIVE_VIS_ENABLE=' "$f" || { echo "[0492b-check] missing LiveVis enable: $f" >&2; exit 1; }
  grep -Fq 'LIVE_PROGRESS=' "$f" || { echo "[0492b-check] missing LIVE_PROGRESS: $f" >&2; exit 1; }
  grep -Fq 'PARTICLE_TYPE_FILTER=' "$f" || { echo "[0492b-check] missing particle filter: $f" >&2; exit 1; }
  grep -Fq 'PREFLIGHT_ONLY=' "$f" || { echo "[0492b-check] missing preflight control: $f" >&2; exit 1; }
done

inj_empty=scripts/run_ok_injection_type1_into_type2_empty.sh
for token in \
  'src-q6-resampling' \
  'SPECIES_RESAMPLING_ENABLE=' \
  'MASS_RECONDITION_ENABLE=' \
  'GAS_MASS_CLOSURE_STRENGTH="${GAS_MASS_CLOSURE_STRENGTH:-0.0}"' \
  'SPECIES_CELL_DIAGNOSTICS_ENABLE="${SPECIES_CELL_DIAGNOSTICS_ENABLE:-false}"' \
  'speciesQ6Mode = ${SPECIES_Q6_MODE}' \
  'INITIAL_DOMAIN_MODE="${INITIAL_DOMAIN_MODE:-empty}"' \
  'SCENARIO_EXPECTATION="${SCENARIO_EXPECTATION:-empty}"' \
  'check_injection_species_0492b.py'; do
  grep -Fq "$token" "$inj_empty" || { echo "[0492b-check] empty injection contract missing: $token" >&2; exit 1; }
done

inj_two=scripts/run_ok_injection_type1_into_type2.sh
for token in \
  'INITIAL_DOMAIN_MODE="${INITIAL_DOMAIN_MODE:-full}"' \
  'SCENARIO_EXPECTATION="${SCENARIO_EXPECTATION:-two_species}"' \
  'GAS_MASS_CLOSURE_STRENGTH="${GAS_MASS_CLOSURE_STRENGTH:-0.0}"' \
  'run_ok_injection_type1_into_type2_empty.sh'; do
  grep -Fq "$token" "$inj_two" || { echo "[0492b-check] two-species wrapper contract missing: $token" >&2; exit 1; }
done

common=scripts/src_mpcd_run_common_0434.sh
for token in \
  'speciesResamplingMassClosureCudaEnable' \
  'speciesResamplingPopulationGuardCudaEnable' \
  'cudaResamplingEmptyRefillSpeciesCompositionEnable' \
  'speciesResamplingTransferCudaEnable' \
  'speciesResamplingCudaResidentValidationEnable' \
  'speciesResamplingCudaResidentMaintenanceStrict' \
  'suite_species_resident_mode_0492a' \
  'particleTypeFilter = ${PARTICLE_TYPE_FILTER}' \
  '[0492a-run-ok] preflight=PASS'; do
  grep -Fq "$token" "$common" || { echo "[0492b-check] common contract missing: $token" >&2; exit 1; }
done

source "$common"
SPECIES_RESAMPLING_ENABLE=true
[[ "$(suite_species_resident_mode_0492a src-q6-resampling periodic)" == fast ]] || { echo '[0492b-check] periodic auto mode is not fast' >&2; exit 1; }
[[ "$(suite_species_resident_mode_0492a src-q6-resampling segmented)" == compatible ]] || { echo '[0492b-check] segmented auto mode is not compatible' >&2; exit 1; }
SPECIES_RESIDENT_MODE=validation
[[ "$(suite_species_resident_mode_0492a src-q6-resampling segmented)" == validation ]] || { echo '[0492b-check] explicit validation mode failed' >&2; exit 1; }
unset SPECIES_RESIDENT_MODE SPECIES_RESAMPLING_ENABLE

echo '[0492b-check] PASS'
