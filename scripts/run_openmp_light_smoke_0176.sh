#!/usr/bin/env bash
set -euo pipefail

# 0176d: smoke wrapper for the OpenMP-light branch.
# By default, internal coding/profiling CSVs are disabled.
# To verify that the development profiles can still be re-enabled, launch with:
#   MPCD_INTERNAL_PROFILES=1 RUN_ROOT=... ./scripts/run_openmp_light_smoke_0176.sh

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

: "${RUN_ROOT:=runs/openmp_light_smoke_0176}"
: "${THREADS:=4}"
: "${STEPS:=50}"
: "${SUMMARY_EVERY:=10}"
: "${RUN_TAG:=openmp_light_0176}"
# Important: respect a caller-supplied value. Do not force 0 here.
: "${MPCD_INTERNAL_PROFILES:=0}"
export MPCD_INTERNAL_PROFILES

rm -rf "$RUN_ROOT"

echo "[0176-light-smoke] root                    : $ROOT_DIR"
echo "[0176-light-smoke] run root                : $RUN_ROOT"
echo "[0176-light-smoke] threads                 : $THREADS"
echo "[0176-light-smoke] steps                   : $STEPS"
echo "[0176-light-smoke] summary every           : $SUMMARY_EVERY"
echo "[0176-light-smoke] MPCD_INTERNAL_PROFILES  : $MPCD_INTERNAL_PROFILES"

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

if [[ "$MPCD_INTERNAL_PROFILES" == "0" ]]; then
  if [[ "$profile_count" != "0" ]]; then
    echo "[0176-light-smoke] ERROR: internal profile files were produced in light mode:" >&2
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
  echo "[0176-light-smoke] PASS: no internal profile files produced in light mode."
else
  if [[ "$profile_count" == "0" ]]; then
    echo "[0176-light-smoke] ERROR: MPCD_INTERNAL_PROFILES=$MPCD_INTERNAL_PROFILES but no internal profile files were produced." >&2
    echo "[0176-light-smoke] Check that the C++ guards use getenv(\"MPCD_INTERNAL_PROFILES\") at runtime and that the binary was rebuilt." >&2
    exit 1
  fi
  echo "[0176-light-smoke] PASS: internal profiles produced when explicitly enabled ($profile_count files)."
fi
