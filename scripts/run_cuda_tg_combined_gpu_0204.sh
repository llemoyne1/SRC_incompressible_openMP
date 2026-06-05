#!/usr/bin/env bash
set -euo pipefail

# 0204 — robust combined CUDA TG validation.
# Fixes the 0203 harness issue where noisy compare output could prevent the
# consolidated CSV from receiving the non-baseline rows. This script writes
# rows using known compare output paths directly and does not stop after a
# metric FAIL in one mode; it records the verdict and continues.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BIN=${BIN:-build/src_mpcd_base_cuda_0204}
ART_DIR=${ART_DIR:-dev_history/artifacts/gpu_cuda_combined_0204}
GRID_CASES=${GRID_CASES:-"64:200 128:100"}
GAMMA=${GAMMA:-20}
THREADS=${THREADS:-8}
SUMMARY_EVERY_DEFAULT=${SUMMARY_EVERY:-50}
SEED_BASE=${SEED_BASE:-1620204}
BATCH_SIZE=${BATCH_SIZE:-20}
RUN_Q6_ONLY=${RUN_Q6_ONLY:-1}
RUN_CELL_ONLY=${RUN_CELL_ONLY:-1}
RUN_COMBINED=${RUN_COMBINED:-1}
CUDA_Q6_DIV_AFTER_MAX=${CUDA_Q6_DIV_AFTER_MAX:-1e-8}
STOP_ON_FAIL=${STOP_ON_FAIL:-0}

mkdir -p "$ART_DIR"

if [[ ! -x "$BIN" ]]; then
  OUT="$BIN" CUDA_ARCH_FLAGS=${CUDA_ARCH_FLAGS:-} bash scripts/build_src_mpcd_cuda_0204.sh
fi
if [[ ! -x "$BIN" ]]; then
  echo "[0204-combined] ERROR: CUDA-enabled binary not found after build: $BIN" >&2
  exit 127
fi

OUT_CSV=${OUT_CSV:-$ART_DIR/cuda_tg_combined_gpu_0204.csv}
printf 'grid,mode,NX,NY,steps,batchSize,elapsed_s,wallTime,speedupWallBaselineOverMode,failed_metrics,compared_metrics,verdict,q6Iterations,q6DivAfterProjectedFluxRms,cellActiveCalls,cellTotalSeconds,cellUploadSeconds,cellKernelSeconds,cellDownloadSeconds,cellReuseBufferFraction,cellAllFluidFastPathFraction,cellUniformMassFastPathFraction,cudaTimingSolves,cudaTimingIterations,cudaTimingBatches,cudaTimingConvergenceDownloads,cudaTimingTotalSeconds,cudaTimingHostReductionSeconds,cudaTimingApplyOperatorSeconds,runRoot,compareCsv,compareSummary\n' > "$OUT_CSV"

run_validation() {
  local nx=$1 ny=$2 steps=$3 root=$4 tag=$5 projection=$6 cell_use=$7
  local summary_every=${SUMMARY_EVERY_OVERRIDE:-$SUMMARY_EVERY_DEFAULT}
  local seed=$((SEED_BASE + nx + steps))
  env BIN="$BIN" BUILD_IF_MISSING=0 CASE_LIST="tg_periodic_full" \
      NX="$nx" NY="$ny" GAMMA="$GAMMA" STEPS="$steps" SUMMARY_EVERY="$summary_every" \
      THREADS="$THREADS" SEED="$seed" DUMP_STATE_EVERY=0 \
      RUN_ROOT="$root" RUN_TAG="$tag" PROJECTION_BACKEND="$projection" \
      MPCD_CUDA_CELL_MOMENTS_USE="$cell_use" \
      MPCD_CUDA_CELL_MOMENTS_REUSE_BUFFERS=${MPCD_CUDA_CELL_MOMENTS_REUSE_BUFFERS:-1} \
      MPCD_CUDA_CELL_MOMENTS_ALL_FLUID_FASTPATH=${MPCD_CUDA_CELL_MOMENTS_ALL_FLUID_FASTPATH:-1} \
      MPCD_CUDA_CELL_MOMENTS_UNIFORM_MASS_FASTPATH=${MPCD_CUDA_CELL_MOMENTS_UNIFORM_MASS_FASTPATH:-1} \
      MPCD_CUDA_CELL_MOMENTS_SHADOW=0 \
      MPCD_CUDA_Q6_TIMING=1 \
      MPCD_CUDA_Q6_DISABLE_PLAN_CACHE=0 \
      MPCD_CUDA_Q6_DEVICE_SCALAR_CG=1 \
      MPCD_CUDA_Q6_LEGACY_HOST_SCALAR_CG=0 \
      MPCD_CUDA_Q6_DEVICE_SCALAR_BATCH="$BATCH_SIZE" \
      MPCD_CUDA_Q6_DEVICE_SCALAR_REDUCTION=0 \
      MPCD_CUDA_Q6_HOST_BLOCK_SUM=1 \
      MPCD_CUDA_Q6_RESIDUAL_NORM_SHORTCUT=0 \
      MPCD_CUDA_Q6_LEGACY_MEAN_REMOVAL_RESIDUAL_NORM=1 \
      bash scripts/run_validation_mono_config_0162.sh
}

compare_to_baseline() {
  local baseline_root=$1 opt_root=$2 out_prefix=$3
  local compare_csv="$ART_DIR/${out_prefix}.csv"
  local compare_summary="$ART_DIR/${out_prefix}_summary.csv"
  python3 scripts/compare_validation_mono_config_0162.py \
    --origin "$baseline_root" \
    --optimized "$opt_root" \
    --out "$compare_csv" \
    --summary-out "$compare_summary"
}

append_mode_row() {
  local label=$1 mode=$2 nx=$3 ny=$4 steps=$5 root=$6 baseline_summary=$7 summary=$8 compare_csv=$9 compare_summary=${10}
  python3 - "$label" "$mode" "$nx" "$ny" "$steps" "$BATCH_SIZE" "$root" "$baseline_summary" "$summary" "$compare_csv" "$compare_summary" "$CUDA_Q6_DIV_AFTER_MAX" "$OUT_CSV" <<'PY'
import csv, math, os, re, sys
(label, mode, nx, ny, steps, batch_size, root, baseline_summary, summary, compare_csv, compare_summary, div_max_s, out_csv) = sys.argv[1:14]
div_max = float(div_max_s)
case_name = 'tg_periodic_full'
fieldnames = ['grid','mode','NX','NY','steps','batchSize','elapsed_s','wallTime','speedupWallBaselineOverMode','failed_metrics','compared_metrics','verdict','q6Iterations','q6DivAfterProjectedFluxRms','cellActiveCalls','cellTotalSeconds','cellUploadSeconds','cellKernelSeconds','cellDownloadSeconds','cellReuseBufferFraction','cellAllFluidFastPathFraction','cellUniformMassFastPathFraction','cudaTimingSolves','cudaTimingIterations','cudaTimingBatches','cudaTimingConvergenceDownloads','cudaTimingTotalSeconds','cudaTimingHostReductionSeconds','cudaTimingApplyOperatorSeconds','runRoot','compareCsv','compareSummary']

def read_one(path, default=None):
    if path == 'none' or not os.path.exists(path):
        if default is not None:
            return default
        raise SystemExit(f'missing required CSV: {path}')
    with open(path, newline='') as f:
        rows = list(csv.DictReader(f))
    if len(rows) != 1:
        raise SystemExit(f'expected one row in {path}, got {len(rows)}')
    return rows[0]

def f(row, key):
    try: return float(row.get(key, 'nan'))
    except Exception: return float('nan')

def i(row, key):
    try: return int(round(float(row.get(key, '0'))))
    except Exception: return 0

base = read_one(baseline_summary)
sumr = read_one(summary)
compare = read_one(compare_summary, {'failed_metrics':'0','compared_metrics':'0','verdict':'PASS'})
failed = int(round(float(compare.get('failed_metrics', '0'))))
compared = int(round(float(compare.get('compared_metrics', '0'))))
verdict = 'PASS' if failed == 0 else 'FAIL'
q6_div = f(sumr, 'q6DivAfterProjectedFluxRms')
if mode in ('q6_cuda', 'combined_cuda') and (not math.isfinite(q6_div) or q6_div > div_max):
    verdict = 'FAIL'
    failed = max(failed, 1)

cell_csv = os.path.join(root, case_name, 'cuda_cell_moments_active_0202.csv')
cell_calls = 0
cell_total = cell_upload = cell_kernel = cell_download = 0.0
reuse_frac = all_fluid_frac = uniform_mass_frac = float('nan')
if os.path.exists(cell_csv):
    with open(cell_csv, newline='') as fp:
        rows = list(csv.DictReader(fp))
    cell_calls = len(rows)
    if cell_calls:
        def vals(key):
            out=[]
            for r in rows:
                try: out.append(float(r.get(key, 'nan')))
                except Exception: out.append(float('nan'))
            return out
        cell_total = sum(vals('totalSeconds'))
        cell_upload = sum(vals('uploadSeconds'))
        cell_kernel = sum(vals('kernelSeconds'))
        cell_download = sum(vals('downloadSeconds'))
        reuse_frac = sum(vals('reusedDeviceBuffers')) / cell_calls
        all_fluid_frac = sum(vals('allFluidFastPath')) / cell_calls
        uniform_mass_frac = sum(vals('uniformMassFastPath')) / cell_calls

time_path = os.path.join(root, f'{case_name}.time')
fields = {}
if os.path.exists(time_path):
    with open(time_path, encoding='utf-8', errors='replace') as fp:
        for raw in fp:
            if '[cuda_q6_timing_0192]' in raw:
                fields = dict(re.findall(r'([A-Za-z0-9_]+)=([^\s]+)', raw.strip()))

def tf(key):
    try: return float(fields.get(key, 'nan'))
    except Exception: return float('nan')

def ti(key):
    try: return int(round(float(fields.get(key, '0'))))
    except Exception: return 0

wall = f(sumr, 'wallTime')
base_wall = f(base, 'wallTime')
row = {
    'grid': label,
    'mode': mode,
    'NX': nx,
    'NY': ny,
    'steps': steps,
    'batchSize': batch_size if mode in ('q6_cuda','combined_cuda') else 0,
    'elapsed_s': f(sumr, 'elapsed_s'),
    'wallTime': wall,
    'speedupWallBaselineOverMode': base_wall / wall if wall > 0 else float('nan'),
    'failed_metrics': failed,
    'compared_metrics': compared,
    'verdict': verdict,
    'q6Iterations': i(sumr, 'q6Iterations'),
    'q6DivAfterProjectedFluxRms': q6_div,
    'cellActiveCalls': cell_calls,
    'cellTotalSeconds': cell_total,
    'cellUploadSeconds': cell_upload,
    'cellKernelSeconds': cell_kernel,
    'cellDownloadSeconds': cell_download,
    'cellReuseBufferFraction': reuse_frac,
    'cellAllFluidFastPathFraction': all_fluid_frac,
    'cellUniformMassFastPathFraction': uniform_mass_frac,
    'cudaTimingSolves': ti('solves'),
    'cudaTimingIterations': ti('iterations'),
    'cudaTimingBatches': ti('deviceScalarCgBatches'),
    'cudaTimingConvergenceDownloads': ti('deviceScalarCgConvergenceDownloads'),
    'cudaTimingTotalSeconds': tf('totalSeconds'),
    'cudaTimingHostReductionSeconds': tf('hostReductionSeconds'),
    'cudaTimingApplyOperatorSeconds': tf('applyOperatorSeconds'),
    'runRoot': root,
    'compareCsv': compare_csv,
    'compareSummary': compare_summary,
}
with open(out_csv, 'a', newline='') as fcsv:
    writer = csv.DictWriter(fcsv, fieldnames=fieldnames)
    writer.writerow(row)
print(f"[0204-combined] {verdict} {label}/{mode}: wall={wall:.6g}s baselineSpeed={row['speedupWallBaselineOverMode']:.3f} failed={failed}/{compared} cell={cell_total:.3g}s q6={row['cudaTimingTotalSeconds']:.3g}s")
PY
}

run_and_record() {
  local label=$1 mode=$2 nx=$3 ny=$4 steps=$5 base_root=$6 root=$7 projection=$8 cell_use=$9
  local tag="cuda0204_${mode}_${label}"
  echo "[0204-combined] running $label/$mode"
  run_validation "$nx" "$ny" "$steps" "$root" "$tag" "$projection" "$cell_use"
  local compare_csv="none" compare_summary="none"
  if [[ "$mode" != "cpu_baseline" ]]; then
    local prefix="cuda_tg_combined_compare_0204_${mode}_${label}"
    compare_csv="$ART_DIR/${prefix}.csv"
    compare_summary="$ART_DIR/${prefix}_summary.csv"
    compare_to_baseline "$base_root" "$root" "$prefix" || true
  fi
  append_mode_row "$label" "$mode" "$nx" "$ny" "$steps" "$root" \
    "$base_root/validation_summary_0162.csv" "$root/validation_summary_0162.csv" "$compare_csv" "$compare_summary"
  local rc=0
  if [[ "$mode" != "cpu_baseline" ]]; then
    rc=$(python3 - "$compare_summary" <<'PY'
import csv, sys, os
p=sys.argv[1]
if not os.path.exists(p):
    print(1); raise SystemExit
with open(p, newline='') as f:
    rows=list(csv.DictReader(f))
print(int(float(rows[0].get('failed_metrics','1'))) if rows else 1)
PY
)
    if [[ "$STOP_ON_FAIL" == "1" && "$rc" != "0" ]]; then
      echo "[0204-combined] stopping because $mode failed metrics ($rc)" >&2
      exit 1
    fi
  fi
}

run_one_grid() {
  local nx=$1 steps=$2 ny=${NY_OVERRIDE:-$nx}
  local label="${nx}x${ny}_s${steps}"
  local base_root="runs/cuda_tg_combined_0204_cpu_${label}"
  run_and_record "$label" cpu_baseline "$nx" "$ny" "$steps" "$base_root" "$base_root" cpu 0
  if [[ "$RUN_Q6_ONLY" == "1" ]]; then
    run_and_record "$label" q6_cuda "$nx" "$ny" "$steps" "$base_root" "runs/cuda_tg_combined_0204_q6_${label}" cuda 0
  fi
  if [[ "$RUN_CELL_ONLY" == "1" ]]; then
    run_and_record "$label" cell_cuda "$nx" "$ny" "$steps" "$base_root" "runs/cuda_tg_combined_0204_cell_${label}" cpu 1
  fi
  if [[ "$RUN_COMBINED" == "1" ]]; then
    run_and_record "$label" combined_cuda "$nx" "$ny" "$steps" "$base_root" "runs/cuda_tg_combined_0204_combined_${label}" cuda 1
  fi
}

for spec in $GRID_CASES; do
  IFS=: read -r nx steps <<< "$spec"
  if [[ -z "${nx:-}" || -z "${steps:-}" ]]; then
    echo "[0204-combined] invalid GRID_CASES entry '$spec' (expected NX:steps)" >&2
    exit 2
  fi
  run_one_grid "$nx" "$steps"
done

echo "[0204-combined] wrote $OUT_CSV"
