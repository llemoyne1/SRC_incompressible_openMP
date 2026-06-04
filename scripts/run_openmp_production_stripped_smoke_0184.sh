#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

: "${RUN_ROOT:=runs/openmp_production_stripped_smoke_0184}"
: "${THREADS:=4}"
: "${STEPS:=50}"
: "${SUMMARY_EVERY:=10}"
: "${RUN_TAG:=openmp_production_stripped_0184}"

rm -rf "$RUN_ROOT"

echo "[0184-production-stripped-smoke] root          : $ROOT_DIR"
echo "[0184-production-stripped-smoke] run root      : $RUN_ROOT"
echo "[0184-production-stripped-smoke] threads       : $THREADS"
echo "[0184-production-stripped-smoke] steps         : $STEPS"
echo "[0184-production-stripped-smoke] summary every : $SUMMARY_EVERY"

RUN_TAG="$RUN_TAG" \
RUN_ROOT="$RUN_ROOT" \
THREADS="$THREADS" \
STEPS="$STEPS" \
SUMMARY_EVERY="$SUMMARY_EVERY" \
./scripts/run_validation_mono_config_0162.sh

profile_count="$(find "$RUN_ROOT" \
  \( -name "phase_profile_*.csv" \
  -o -name "q6_cg_profile_*.csv" \
  -o -name "deposit_profile_*.csv" \
  -o -name "resampling_guard_profile_*.csv" \
  -o -name "post_guard_profile_*.csv" \
  -o -name "post_guard_equivalence*.csv" \
  -o -name "post_guard_equivalence_trace_*.csv" \) \
  -type f | wc -l)"

if [[ "$profile_count" != "0" ]]; then
  echo "[0184-production-stripped-smoke] ERROR: internal profile files were produced:" >&2
  find "$RUN_ROOT" \
    \( -name "phase_profile_*.csv" \
    -o -name "q6_cg_profile_*.csv" \
    -o -name "deposit_profile_*.csv" \
    -o -name "resampling_guard_profile_*.csv" \
    -o -name "post_guard_profile_*.csv" \
    -o -name "post_guard_equivalence*.csv" \
    -o -name "post_guard_equivalence_trace_*.csv" \) -type f -print >&2
  exit 1
fi

echo "[0184-production-stripped-smoke] PASS: no internal profile files produced."
