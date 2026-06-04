#!/usr/bin/env bash
set -euo pipefail

# 0184: compare clean/openmp-light against clean/openmp-production-stripped.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REF_ROOT="${REF_ROOT:-../SRC_openMP_light}"
RUN_TAG_REF="${RUN_TAG_REF:-light_ref_0184}"
RUN_TAG_STRIPPED="${RUN_TAG_STRIPPED:-production_stripped_0184}"
RUN_ROOT_REF="${RUN_ROOT_REF:-runs/validation_0184_light_ref}"
RUN_ROOT_STRIPPED="${RUN_ROOT_STRIPPED:-runs/validation_0184_production_stripped}"
THREADS="${THREADS:-8}"
STEPS="${STEPS:-1000}"
SUMMARY_EVERY="${SUMMARY_EVERY:-100}"
COMPARE_OUT="${COMPARE_OUT:-validation_compare_0184.csv}"
COMPARE_SUMMARY_OUT="${COMPARE_SUMMARY_OUT:-validation_compare_summary_0184.csv}"
BUILD_REF="${BUILD_REF:-0}"
BUILD_STRIPPED="${BUILD_STRIPPED:-1}"

if [[ "$REF_ROOT" != /* ]]; then
  REF_ABS="$(cd "$ROOT" && cd "$REF_ROOT" && pwd)"
else
  REF_ABS="$REF_ROOT"
fi
STRIPPED_ABS="$ROOT"

echo "[0184-validation] stripped root : $STRIPPED_ABS"
echo "[0184-validation] ref root      : $REF_ABS"
echo "[0184-validation] threads/steps : $THREADS / $STEPS"

if [[ "$BUILD_REF" == "1" ]]; then
  (cd "$REF_ABS" && BUILD_PROFILE=native ./scripts/build_src_mpcd_base_optimized_0156.sh)
fi
if [[ "$BUILD_STRIPPED" == "1" ]]; then
  (cd "$STRIPPED_ABS" && BUILD_PROFILE=native ./scripts/build_src_mpcd_base_optimized_0156.sh)
fi

(cd "$REF_ABS" && \
  RUN_TAG="$RUN_TAG_REF" \
  RUN_ROOT="$RUN_ROOT_REF" \
  THREADS="$THREADS" \
  STEPS="$STEPS" \
  SUMMARY_EVERY="$SUMMARY_EVERY" \
  ./scripts/run_validation_mono_config_0162.sh)

(cd "$STRIPPED_ABS" && \
  RUN_TAG="$RUN_TAG_STRIPPED" \
  RUN_ROOT="$RUN_ROOT_STRIPPED" \
  THREADS="$THREADS" \
  STEPS="$STEPS" \
  SUMMARY_EVERY="$SUMMARY_EVERY" \
  ./scripts/run_validation_mono_config_0162.sh)

(cd "$STRIPPED_ABS" && \
  python3 scripts/compare_validation_mono_config_0162.py \
    --origin "$REF_ABS/$RUN_ROOT_REF" \
    --optimized "$STRIPPED_ABS/$RUN_ROOT_STRIPPED" \
    --out "$COMPARE_OUT" \
    --summary-out "$COMPARE_SUMMARY_OUT")

echo "[0184-validation] wrote $STRIPPED_ABS/$COMPARE_OUT"
echo "[0184-validation] wrote $STRIPPED_ABS/$COMPARE_SUMMARY_OUT"
