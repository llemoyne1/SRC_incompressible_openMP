#!/usr/bin/env bash
set -euo pipefail

# Final validation helper for the OpenMP-light branch.
# It compares SRC_openMP_light against a reference optimized directory using the
# existing mono-configuration validation/comparison scripts.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REF_ROOT="${REF_ROOT:-../SRC_openMP_optimized}"
RUN_TAG_REF="${RUN_TAG_REF:-optimized_ref_0182}"
RUN_TAG_LIGHT="${RUN_TAG_LIGHT:-light_0182}"
RUN_ROOT_REF="${RUN_ROOT_REF:-runs/validation_final_0182_optimized_ref}"
RUN_ROOT_LIGHT="${RUN_ROOT_LIGHT:-runs/validation_final_0182_light}"
THREADS="${THREADS:-8}"
STEPS="${STEPS:-1000}"
SUMMARY_EVERY="${SUMMARY_EVERY:-100}"
COMPARE_OUT="${COMPARE_OUT:-validation_compare_0182.csv}"
COMPARE_SUMMARY_OUT="${COMPARE_SUMMARY_OUT:-validation_compare_summary_0182.csv}"
BUILD_REF="${BUILD_REF:-0}"
BUILD_LIGHT="${BUILD_LIGHT:-1}"

if [[ ! -d "$ROOT" ]]; then
  echo "Cannot resolve root" >&2
  exit 2
fi
if [[ ! -d "$ROOT/$REF_ROOT" && ! -d "$REF_ROOT" ]]; then
  echo "Reference root not found: $REF_ROOT" >&2
  echo "Set REF_ROOT=/path/to/SRC_openMP_optimized if needed." >&2
  exit 2
fi

if [[ "$REF_ROOT" != /* ]]; then
  REF_ABS="$(cd "$ROOT" && cd "$REF_ROOT" && pwd)"
else
  REF_ABS="$REF_ROOT"
fi

LIGHT_ABS="$ROOT"

echo "[0182-final-validation] light root: $LIGHT_ABS"
echo "[0182-final-validation] ref root  : $REF_ABS"
echo "[0182-final-validation] threads/steps: $THREADS / $STEPS"

if [[ "$BUILD_REF" == "1" ]]; then
  echo "[0182-final-validation] building reference"
  (cd "$REF_ABS" && BUILD_PROFILE=native ./scripts/build_src_mpcd_base_optimized_0156.sh)
fi
if [[ "$BUILD_LIGHT" == "1" ]]; then
  echo "[0182-final-validation] building light"
  (cd "$LIGHT_ABS" && BUILD_PROFILE=native ./scripts/build_src_mpcd_base_optimized_0156.sh)
fi

echo "[0182-final-validation] running reference validation"
(cd "$REF_ABS" && \
  RUN_TAG="$RUN_TAG_REF" \
  RUN_ROOT="$RUN_ROOT_REF" \
  THREADS="$THREADS" \
  STEPS="$STEPS" \
  SUMMARY_EVERY="$SUMMARY_EVERY" \
  ./scripts/run_validation_mono_config_0162.sh)

echo "[0182-final-validation] running light validation"
(cd "$LIGHT_ABS" && \
  MPCD_INTERNAL_PROFILES=0 \
  RUN_TAG="$RUN_TAG_LIGHT" \
  RUN_ROOT="$RUN_ROOT_LIGHT" \
  THREADS="$THREADS" \
  STEPS="$STEPS" \
  SUMMARY_EVERY="$SUMMARY_EVERY" \
  ./scripts/run_validation_mono_config_0162.sh)

echo "[0182-final-validation] comparing"
(cd "$LIGHT_ABS" && \
  python3 scripts/compare_validation_mono_config_0162.py \
    --origin "$REF_ABS/$RUN_ROOT_REF" \
    --optimized "$LIGHT_ABS/$RUN_ROOT_LIGHT" \
    --out "$COMPARE_OUT" \
    --summary-out "$COMPARE_SUMMARY_OUT")

echo "[0182-final-validation] wrote $LIGHT_ABS/$COMPARE_OUT"
echo "[0182-final-validation] wrote $LIGHT_ABS/$COMPARE_SUMMARY_OUT"
