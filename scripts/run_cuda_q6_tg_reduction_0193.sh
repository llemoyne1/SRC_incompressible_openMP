#!/usr/bin/env bash
set -euo pipefail

# 0193 — CUDA Q6 reduction cleanup regression for the integrated Taylor--Green
# subset.  This does not expand the supported physics; it instruments the CUDA CG
# path and tests whether the CPU/CUDA balance changes with grid size.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BIN=${BIN:-build/src_mpcd_base_cuda_0193}
ART_DIR=${ART_DIR:-dev_history/artifacts/gpu_cuda_integration_0193}
GRID_CASES=${GRID_CASES:-"64:1000 128:500"}
# For a heavier local experiment, use for example:
#   GRID_CASES='64:1000 128:500 256:200'
GAMMA=${GAMMA:-20}
THREADS=${THREADS:-8}
SUMMARY_EVERY_DEFAULT=${SUMMARY_EVERY:-100}
SEED_BASE=${SEED_BASE:-1620193}
CUDA_Q6_DIV_AFTER_MAX=${CUDA_Q6_DIV_AFTER_MAX:-1e-8}
RUN_UNSUPPORTED_CHECK=${RUN_UNSUPPORTED_CHECK:-1}

mkdir -p "$ART_DIR"

if [[ ! -x "$BIN" ]]; then
  OUT="$BIN" CUDA_ARCH_FLAGS=${CUDA_ARCH_FLAGS:-} bash scripts/build_src_mpcd_cuda_0193.sh
fi
if [[ ! -x "$BIN" ]]; then
  echo "[0193-cuda-reduction] ERROR: CUDA-enabled binary not found after build: $BIN" >&2
  exit 127
fi

SCALING_CSV=${SCALING_CSV:-$ART_DIR/cuda_q6_tg_reduction_scaling_0193.csv}
printf 'grid,NX,NY,steps,cpuElapsed_s,cudaElapsed_s,cpuWallTime,cudaWallTime,speedupElapsedCpuOverCuda,speedupWallCpuOverCuda,cpuQ6Iterations,cudaQ6Iterations,cpuQ6DivAfter,cudaQ6DivAfter,cudaTimingSolves,cudaTimingIterations,cudaTimingReductions,cudaTimingOperatorApplications,cudaTimingTotalSeconds,cudaTimingAvgSolveSeconds,cudaTimingAvgIterationSeconds,cudaTimingHostReductionSeconds,cudaTimingApplyOperatorSeconds,cudaTimingAxpyResidualSeconds,cudaTimingUpdateDirectionSeconds,cudaTimingMeanRemovalSeconds,cudaTimingDownloadPhiSeconds,cudaTimingRaw\n' > "$SCALING_CSV"

run_one() {
  local nx=$1
  local steps=$2
  local ny=${NY_OVERRIDE:-$nx}
  local summary_every=${SUMMARY_EVERY_OVERRIDE:-$SUMMARY_EVERY_DEFAULT}
  local seed=$((SEED_BASE + nx + steps))
  local label="${nx}x${ny}_s${steps}"
  local cpu_root="runs/cuda_q6_tg_cpu_ref_0193_${label}"
  local cuda_root="runs/cuda_q6_tg_cuda_0193_${label}"
  local compare_out="$ART_DIR/cuda_q6_tg_compare_0193_${label}.csv"
  local compare_summary_out="$ART_DIR/cuda_q6_tg_compare_summary_0193_${label}.csv"

  echo "[0193-cuda-reduction] CPU reference $label"
  env BIN="$BIN" BUILD_IF_MISSING=0 CASE_LIST="tg_periodic_full" \
      NX="$nx" NY="$ny" GAMMA="$GAMMA" STEPS="$steps" SUMMARY_EVERY="$summary_every" \
      THREADS="$THREADS" SEED="$seed" DUMP_STATE_EVERY=0 \
      RUN_ROOT="$cpu_root" RUN_TAG="cuda0193_cpu_${label}" PROJECTION_BACKEND=cpu \
      bash scripts/run_validation_mono_config_0162.sh

  echo "[0193-cuda-reduction] CUDA instrumented $label"
  env BIN="$BIN" BUILD_IF_MISSING=0 CASE_LIST="tg_periodic_full" \
      NX="$nx" NY="$ny" GAMMA="$GAMMA" STEPS="$steps" SUMMARY_EVERY="$summary_every" \
      THREADS="$THREADS" SEED="$seed" DUMP_STATE_EVERY=0 \
      RUN_ROOT="$cuda_root" RUN_TAG="cuda0193_cuda_${label}" PROJECTION_BACKEND=cuda \
      MPCD_CUDA_Q6_TIMING=1 MPCD_CUDA_Q6_DISABLE_PLAN_CACHE=0 \
      MPCD_CUDA_Q6_HOST_BLOCK_SUM="${MPCD_CUDA_Q6_HOST_BLOCK_SUM:-0}" \
      MPCD_CUDA_Q6_DEBUG_SYNC="${MPCD_CUDA_Q6_DEBUG_SYNC:-0}" \
      bash scripts/run_validation_mono_config_0162.sh

  python3 scripts/compare_validation_mono_config_0162.py \
    --origin "$cpu_root" \
    --optimized "$cuda_root" \
    --out "$compare_out" \
    --summary-out "$compare_summary_out"

  python3 - "$label" "$nx" "$ny" "$steps" "$cpu_root/validation_summary_0162.csv" "$cuda_root/validation_summary_0162.csv" "$cuda_root/tg_periodic_full.time" "$CUDA_Q6_DIV_AFTER_MAX" "$SCALING_CSV" <<'PY'
import csv
import math
import re
import sys

(label, nx, ny, steps, cpu_summary, cuda_summary, cuda_time, div_max_s, out_csv) = sys.argv[1:10]
div_max = float(div_max_s)

def read_one(path):
    with open(path, newline='') as f:
        rows = list(csv.DictReader(f))
    if len(rows) != 1:
        raise SystemExit(f"expected one row in {path}, got {len(rows)}")
    return rows[0]

def f(row, key):
    try:
        return float(row.get(key, 'nan'))
    except ValueError:
        return float('nan')

cpu = read_one(cpu_summary)
cuda = read_one(cuda_summary)
line = ''
with open(cuda_time, encoding='utf-8', errors='replace') as fp:
    for raw in fp:
        if '[cuda_q6_timing_0192]' in raw:
            line = raw.strip()
if not line:
    raise SystemExit(f"missing [cuda_q6_timing_0192] line in {cuda_time}")
fields = dict(re.findall(r'([A-Za-z0-9_]+)=([^\s]+)', line))

def tf(key):
    try:
        return float(fields.get(key, 'nan'))
    except ValueError:
        return float('nan')

def ti(key):
    try:
        return int(float(fields.get(key, '0')))
    except ValueError:
        return 0

cpu_elapsed = f(cpu, 'elapsed_s')
cuda_elapsed = f(cuda, 'elapsed_s')
cpu_wall = f(cpu, 'wallTime')
cuda_wall = f(cuda, 'wallTime')
cpu_iter = int(round(f(cpu, 'q6Iterations')))
cuda_iter = int(round(f(cuda, 'q6Iterations')))
cpu_div = f(cpu, 'q6DivAfterProjectedFluxRms')
cuda_div = f(cuda, 'q6DivAfterProjectedFluxRms')
if not math.isfinite(cuda_div) or cuda_div > div_max:
    raise SystemExit(f"CUDA Q6 divAfter too large for {label}: {cuda_div} > {div_max}")
if cpu_iter != cuda_iter:
    raise SystemExit(f"CPU/CUDA q6Iterations mismatch for {label}: {cpu_iter} vs {cuda_iter}")
row = {
    'grid': label, 'NX': nx, 'NY': ny, 'steps': steps,
    'cpuElapsed_s': cpu_elapsed,
    'cudaElapsed_s': cuda_elapsed,
    'cpuWallTime': cpu_wall,
    'cudaWallTime': cuda_wall,
    'speedupElapsedCpuOverCuda': cpu_elapsed / cuda_elapsed if cuda_elapsed > 0 else float('nan'),
    'speedupWallCpuOverCuda': cpu_wall / cuda_wall if cuda_wall > 0 else float('nan'),
    'cpuQ6Iterations': cpu_iter,
    'cudaQ6Iterations': cuda_iter,
    'cpuQ6DivAfter': cpu_div,
    'cudaQ6DivAfter': cuda_div,
    'cudaTimingSolves': ti('solves'),
    'cudaTimingIterations': ti('iterations'),
    'cudaTimingReductions': ti('reductions'),
    'cudaTimingOperatorApplications': ti('operatorApplications'),
    'cudaTimingTotalSeconds': tf('totalSeconds'),
    'cudaTimingAvgSolveSeconds': tf('avgSolveSeconds'),
    'cudaTimingAvgIterationSeconds': tf('avgIterationSeconds'),
    'cudaTimingHostReductionSeconds': tf('hostReductionSeconds'),
    'cudaTimingApplyOperatorSeconds': tf('applyOperatorSeconds'),
    'cudaTimingAxpyResidualSeconds': tf('axpyResidualSeconds'),
    'cudaTimingUpdateDirectionSeconds': tf('updateDirectionSeconds'),
    'cudaTimingMeanRemovalSeconds': tf('meanRemovalSeconds'),
    'cudaTimingDownloadPhiSeconds': tf('downloadPhiSeconds'),
    'cudaTimingRaw': line,
}
with open(out_csv, 'a', newline='') as f:
    writer = csv.DictWriter(f, fieldnames=list(row.keys()))
    writer.writerow(row)
print(f"[0193-cuda-reduction] PASS {label}: speedup wall CPU/CUDA={row['speedupWallCpuOverCuda']:.3f}, cudaTimingTotal={row['cudaTimingTotalSeconds']:.3f}s")
PY
}

for spec in $GRID_CASES; do
  nx=${spec%%:*}
  steps=${spec#*:}
  if [[ "$nx" == "$steps" ]]; then
    steps=${STEPS:-1000}
  fi
  run_one "$nx" "$steps"
done

if [[ "$RUN_UNSUPPORTED_CHECK" == "1" ]]; then
  echo "[0193-cuda-reduction] Checking that non-periodic Poiseuille remains rejected by projectionBackend=cuda."
  FAIL_ROOT=${FAIL_ROOT:-runs/cuda_q6_unsupported_expected_fail_0193}
  rm -rf "$FAIL_ROOT"
  set +e
  env BIN="$BIN" BUILD_IF_MISSING=0 CASE_LIST="poiseuille_wall_full" \
      RUN_ROOT="$FAIL_ROOT" RUN_TAG="cuda0193_expected_unsupported" \
      PROJECTION_BACKEND=cuda NX=16 NY=16 GAMMA=4 STEPS=1 SUMMARY_EVERY=1 THREADS=2 \
      bash scripts/run_validation_mono_config_0162.sh \
      > "$ART_DIR/cuda_q6_unsupported_stdout_0193.log" \
      2> "$ART_DIR/cuda_q6_unsupported_stderr_0193.log"
  status=$?
  set -e
  if [[ $status -eq 0 ]]; then
    echo "[0193-cuda-reduction] ERROR: unsupported non-periodic CUDA Q6 case unexpectedly succeeded." >&2
    exit 1
  fi
  if ! grep -R "fully periodic, unmasked" "$ART_DIR/cuda_q6_unsupported_stderr_0193.log" "$FAIL_ROOT" >/dev/null 2>&1; then
    echo "[0193-cuda-reduction] ERROR: unsupported-case failure did not contain the expected guard message." >&2
    exit 1
  fi
  echo "[0193-cuda-reduction] PASS: unsupported non-periodic CUDA Q6 case failed explicitly."
fi

echo "[0193-cuda-reduction] wrote $SCALING_CSV"
echo "[0193-cuda-reduction] PASS"
