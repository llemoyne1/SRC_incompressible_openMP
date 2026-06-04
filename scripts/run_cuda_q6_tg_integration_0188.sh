#!/usr/bin/env bash
set -euo pipefail

# 0188 — first integrated CUDA Q6 simulation test.
# Runs Taylor--Green periodic Q6+resampling twice with the same CUDA-enabled
# executable: projectionBackend=cpu as reference, then projectionBackend=cuda.
# CUDA is intentionally supported only for the fully periodic, unmasked subset.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BIN=${BIN:-build/src_mpcd_base_cuda_0188}
RUN_ROOT_CPU=${RUN_ROOT_CPU:-runs/cuda_q6_tg_cpu_ref_0188}
RUN_ROOT_CUDA=${RUN_ROOT_CUDA:-runs/cuda_q6_tg_cuda_0188}
COMPARE_OUT=${COMPARE_OUT:-dev_history/artifacts/gpu_cuda_integration_0188/cuda_q6_tg_compare_0188.csv}
COMPARE_SUMMARY_OUT=${COMPARE_SUMMARY_OUT:-dev_history/artifacts/gpu_cuda_integration_0188/cuda_q6_tg_compare_summary_0188.csv}
CHECK_UNSUPPORTED=${CHECK_UNSUPPORTED:-1}

mkdir -p "$(dirname "$COMPARE_OUT")"

if [[ ! -x "$BIN" ]]; then
  CUDA_ARCH_FLAGS=${CUDA_ARCH_FLAGS:-} bash scripts/build_src_mpcd_cuda_0188.sh
fi
if [[ ! -x "$BIN" ]]; then
  echo "[0188-cuda-tg] ERROR: CUDA-enabled binary not found after build: $BIN" >&2
  exit 127
fi

COMMON_ENV=(
  BIN="$BIN"
  BUILD_IF_MISSING=0
  CASE_LIST="tg_periodic_full"
  NX="${NX:-64}"
  NY="${NY:-64}"
  GAMMA="${GAMMA:-20}"
  STEPS="${STEPS:-1000}"
  SUMMARY_EVERY="${SUMMARY_EVERY:-100}"
  THREADS="${THREADS:-8}"
  SEED="${SEED:-1620188}"
  DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-0}"
)

echo "[0188-cuda-tg] CPU reference run: $RUN_ROOT_CPU"
env "${COMMON_ENV[@]}" \
  RUN_ROOT="$RUN_ROOT_CPU" \
  RUN_TAG="cuda0188_cpu_reference" \
  PROJECTION_BACKEND=cpu \
  bash scripts/run_validation_mono_config_0162.sh

echo "[0188-cuda-tg] CUDA run: $RUN_ROOT_CUDA"
env "${COMMON_ENV[@]}" \
  RUN_ROOT="$RUN_ROOT_CUDA" \
  RUN_TAG="cuda0188_cuda_periodic" \
  PROJECTION_BACKEND=cuda \
  bash scripts/run_validation_mono_config_0162.sh

python3 scripts/compare_validation_mono_config_0162.py \
  --origin "$RUN_ROOT_CPU" \
  --optimized "$RUN_ROOT_CUDA" \
  --out "$COMPARE_OUT" \
  --summary-out "$COMPARE_SUMMARY_OUT"

if [[ "$CHECK_UNSUPPORTED" == "1" ]]; then
  echo "[0188-cuda-tg] Checking that non-periodic Poiseuille remains rejected by projectionBackend=cuda."
  FAIL_ROOT=${FAIL_ROOT:-runs/cuda_q6_unsupported_expected_fail_0188}
  rm -rf "$FAIL_ROOT"
  set +e
  env BIN="$BIN" BUILD_IF_MISSING=0 CASE_LIST="poiseuille_wall_full" \
      RUN_ROOT="$FAIL_ROOT" RUN_TAG="cuda0188_expected_unsupported" \
      PROJECTION_BACKEND=cuda NX=16 NY=16 GAMMA=4 STEPS=1 SUMMARY_EVERY=1 THREADS=2 \
      bash scripts/run_validation_mono_config_0162.sh \
      > dev_history/artifacts/gpu_cuda_integration_0188/cuda_q6_unsupported_stdout_0188.log \
      2> dev_history/artifacts/gpu_cuda_integration_0188/cuda_q6_unsupported_stderr_0188.log
  status=$?
  set -e
  if [[ $status -eq 0 ]]; then
    echo "[0188-cuda-tg] ERROR: unsupported non-periodic CUDA Q6 case unexpectedly succeeded." >&2
    exit 1
  fi
  if ! grep -R "fully periodic, unmasked" dev_history/artifacts/gpu_cuda_integration_0188/cuda_q6_unsupported_stderr_0188.log "$FAIL_ROOT" >/dev/null 2>&1; then
    echo "[0188-cuda-tg] ERROR: unsupported-case failure did not contain the expected guard message." >&2
    exit 1
  fi
  echo "[0188-cuda-tg] PASS: unsupported non-periodic CUDA Q6 case failed explicitly."
fi

echo "[0188-cuda-tg] PASS: integrated periodic CUDA Q6 comparison completed."
echo "[0188-cuda-tg] Compare summary: $COMPARE_SUMMARY_OUT"
