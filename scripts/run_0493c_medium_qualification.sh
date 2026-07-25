#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"
export RUN_ROOT="${RUN_ROOT:-runs/0493c_medium_qualification}"
export CASE_GROUP="${CASE_GROUP:-medium}"
export NX="${NX:-48}"
export NY="${NY:-24}"
export GAMMA="${GAMMA:-10}"
export STEPS="${STEPS:-300}"
export SUMMARY_EVERY="${SUMMARY_EVERY:-10}"
export THREADS="${THREADS:-8}"
export LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
export CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"
export REQUIRE_ACTIVITY="${REQUIRE_ACTIVITY:-1}"
export REQUIRE_DIRECT_TRANSFER="${REQUIRE_DIRECT_TRANSFER:-1}"
exec bash scripts/run_0493c_species_resampling_qualification.sh
