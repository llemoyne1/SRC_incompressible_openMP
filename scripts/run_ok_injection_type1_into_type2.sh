#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

# 0492b true two-species profile: a type-1 liquid jet enters a domain that is
# initially filled with type-2 gas. The implementation remains in the shared
# runner so that flags, LiveVis and topology guards cannot drift.
BIN="${BIN:-${SRC_MPCD_DEFAULT_BIN_0434:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
PARTICLE_TYPE_FILTER="${PARTICLE_TYPE_FILTER:--1}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"

export BIN LIVE_VIS_ENABLE LIVE_PROGRESS PARTICLE_TYPE_FILTER PREFLIGHT_ONLY
export INITIAL_DOMAIN_MODE="${INITIAL_DOMAIN_MODE:-full}"
export SCENARIO_EXPECTATION="${SCENARIO_EXPECTATION:-two_species}"
export PHYSICS_LABEL="${PHYSICS_LABEL:-liquid_type1_into_gas_type2}"
export GAS_MASS_CLOSURE_STRENGTH="${GAS_MASS_CLOSURE_STRENGTH:-0.0}"
export SPECIES_CELL_DIAGNOSTICS_ENABLE="${SPECIES_CELL_DIAGNOSTICS_ENABLE:-false}"
export POSTCHECK_SPECIES_ENABLE="${POSTCHECK_SPECIES_ENABLE:-true}"
export REQUIRE_MIXED_CELL_AT_END="${REQUIRE_MIXED_CELL_AT_END:-false}"

exec "$ROOT/scripts/run_ok_injection_type1_into_type2_empty.sh" "$@"
