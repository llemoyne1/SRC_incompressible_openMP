#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

# 0493w4 true two-species profile: type 1 enters a domain initially filled
# with type 2. INJECT_PHASE and BACKGROUND_PHASE independently select liquid
# or gas; implementation remains in the shared runner so flags cannot drift.
BIN="${BIN:-${SRC_MPCD_DEFAULT_BIN_0434:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
PARTICLE_TYPE_FILTER="${PARTICLE_TYPE_FILTER:--1}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"

export BIN LIVE_VIS_ENABLE LIVE_PROGRESS PARTICLE_TYPE_FILTER PREFLIGHT_ONLY
export INITIAL_DOMAIN_MODE="${INITIAL_DOMAIN_MODE:-full}"
export SCENARIO_EXPECTATION="${SCENARIO_EXPECTATION:-two_species}"
export INJECT_PHASE="${INJECT_PHASE:-liquid}"
export BACKGROUND_PHASE="${BACKGROUND_PHASE:-gas}"
export PHYSICS_LABEL="${PHYSICS_LABEL:-${INJECT_PHASE}_type1_into_${BACKGROUND_PHASE}_type2}"
export SPECIES_CELL_DIAGNOSTICS_ENABLE="${SPECIES_CELL_DIAGNOSTICS_ENABLE:-false}"
export POSTCHECK_SPECIES_ENABLE="${POSTCHECK_SPECIES_ENABLE:-true}"
export REQUIRE_MIXED_CELL_AT_END="${REQUIRE_MIXED_CELL_AT_END:-false}"

exec "$ROOT/scripts/run_ok_injection_type1_into_type2_empty.sh" "$@"
