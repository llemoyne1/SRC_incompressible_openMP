#!/usr/bin/env bash
set -euo pipefail

# 0184 — GPU backend scaffold smoke for the SRC_GPU branch.
# This does not validate a real GPU kernel yet. It verifies that:
#   1) projectionBackend=cpu preserves the validated path;
#   2) projectionBackend=auto falls back explicitly to the CPU path and compares cleanly;
#   3) projectionBackend=openmp_target fails loudly instead of pretending to run on GPU.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

: "${RUN_ROOT_CPU:=runs/gpu_projection_backend_scaffold_0184_cpu}"
: "${RUN_ROOT_AUTO:=runs/gpu_projection_backend_scaffold_0184_auto}"
: "${RUN_ROOT_FAIL:=runs/gpu_projection_backend_scaffold_0184_openmp_target_requested}"
: "${COMPARE_OUT:=validation_compare_gpu_backend_scaffold_0184.csv}"
: "${COMPARE_SUMMARY_OUT:=validation_compare_gpu_backend_scaffold_summary_0184.csv}"
: "${BUILD:=1}"
: "${THREADS:=4}"
: "${STEPS:=20}"
: "${SUMMARY_EVERY:=10}"
: "${NX:=32}"
: "${NY:=32}"
: "${GAMMA:=12}"
: "${CASE_LIST:=tg_periodic_full poiseuille_wall_full open_rect_obstacle_full piston_virial_full}"
: "${EXPECT_UNIMPLEMENTED_GPU_FAILURE:=1}"

export MPCD_INTERNAL_PROFILES=${MPCD_INTERNAL_PROFILES:-0}

if [[ "$BUILD" == "1" ]]; then
  if [[ -x scripts/build_src_mpcd_base_optimized_0156.sh ]]; then
    BUILD_PROFILE=${BUILD_PROFILE:-native} bash scripts/build_src_mpcd_base_optimized_0156.sh
  else
    bash scripts/build_src_mpcd_base.sh
  fi
fi

printf '[0184-gpu-scaffold] root                 : %s\n' "$ROOT"
printf '[0184-gpu-scaffold] cpu run root         : %s\n' "$RUN_ROOT_CPU"
printf '[0184-gpu-scaffold] auto run root        : %s\n' "$RUN_ROOT_AUTO"
printf '[0184-gpu-scaffold] threads/steps/grid   : %s / %s / %sx%s\n' "$THREADS" "$STEPS" "$NX" "$NY"
printf '[0184-gpu-scaffold] cases                : %s\n' "$CASE_LIST"

PROJECTION_BACKEND=cpu \
RUN_TAG=gpu_scaffold_cpu_0184 \
RUN_ROOT="$RUN_ROOT_CPU" \
THREADS="$THREADS" STEPS="$STEPS" SUMMARY_EVERY="$SUMMARY_EVERY" \
NX="$NX" NY="$NY" GAMMA="$GAMMA" CASE_LIST="$CASE_LIST" \
bash scripts/run_validation_mono_config_0162.sh

PROJECTION_BACKEND=auto \
RUN_TAG=gpu_scaffold_auto_fallback_0184 \
RUN_ROOT="$RUN_ROOT_AUTO" \
THREADS="$THREADS" STEPS="$STEPS" SUMMARY_EVERY="$SUMMARY_EVERY" \
NX="$NX" NY="$NY" GAMMA="$GAMMA" CASE_LIST="$CASE_LIST" \
bash scripts/run_validation_mono_config_0162.sh

python3 scripts/compare_validation_mono_config_0162.py \
  --origin "$RUN_ROOT_CPU" \
  --optimized "$RUN_ROOT_AUTO" \
  --out "$COMPARE_OUT" \
  --summary-out "$COMPARE_SUMMARY_OUT"

if [[ "$EXPECT_UNIMPLEMENTED_GPU_FAILURE" == "1" ]]; then
  set +e
  PROJECTION_BACKEND=openmp_target \
  RUN_TAG=gpu_scaffold_openmp_target_expected_fail_0184 \
  RUN_ROOT="$RUN_ROOT_FAIL" \
  THREADS="$THREADS" STEPS=1 SUMMARY_EVERY=1 \
  NX="$NX" NY="$NY" GAMMA="$GAMMA" CASE_LIST=tg_periodic_full \
  bash scripts/run_validation_mono_config_0162.sh >/tmp/gpu_scaffold_0184_openmp_target.stdout 2>/tmp/gpu_scaffold_0184_openmp_target.stderr
  status=$?
  set -e
  if [[ "$status" == "0" ]]; then
    echo '[0184-gpu-scaffold] ERROR: projectionBackend=openmp_target unexpectedly succeeded, but no real GPU kernel is implemented in 0184.' >&2
    exit 1
  fi
  if ! grep -R "projectionBackend=openmp_target" "$RUN_ROOT_FAIL" /tmp/gpu_scaffold_0184_openmp_target.stderr >/dev/null 2>&1; then
    echo '[0184-gpu-scaffold] ERROR: openmp_target failure did not contain the expected explicit backend message.' >&2
    echo '[0184-gpu-scaffold] stdout:' >&2
    cat /tmp/gpu_scaffold_0184_openmp_target.stdout >&2 || true
    echo '[0184-gpu-scaffold] stderr:' >&2
    cat /tmp/gpu_scaffold_0184_openmp_target.stderr >&2 || true
    exit 1
  fi
  echo '[0184-gpu-scaffold] PASS: openmp_target request fails explicitly until a real backend is implemented.'
fi

echo "[0184-gpu-scaffold] wrote $COMPARE_OUT"
echo "[0184-gpu-scaffold] wrote $COMPARE_SUMMARY_OUT"
echo '[0184-gpu-scaffold] PASS'
