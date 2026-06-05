#!/usr/bin/env bash
set -euo pipefail

# 0208 — combined TG validation for the current CUDA stack:
#   Q6 CUDA + active particle-to-cell moments CUDA + active cell thermostat CUDA.
# This is a harness-only patch: no new numerical kernel is introduced.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BIN=${BIN:-build/src_mpcd_base_cuda_0208}
ART_DIR=${ART_DIR:-dev_history/artifacts/gpu_cuda_combined_0208}
GRID_CASES=${GRID_CASES:-"64:200 128:100"}
GAMMA=${GAMMA:-20}
THREADS=${THREADS:-8}
SUMMARY_EVERY_DEFAULT=${SUMMARY_EVERY:-50}
SEED_BASE=${SEED_BASE:-1620208}
BATCH_SIZE=${BATCH_SIZE:-20}
CASE_LIST=${CASE_LIST:-tg_periodic_full}
CUDA_Q6_DIV_AFTER_MAX=${CUDA_Q6_DIV_AFTER_MAX:-1e-8}
STOP_ON_FAIL=${STOP_ON_FAIL:-0}

# Default modes keep the run count manageable while still isolating each block.
# Available modes: cpu_baseline, cell_cuda, thermostat_cuda, cell_thermostat_cuda,
#                  q6_cuda, q6_cell_cuda, q6_thermostat_cuda, full_cuda
MODES=${MODES:-"cpu_baseline cell_cuda thermostat_cuda cell_thermostat_cuda q6_cuda full_cuda"}

mkdir -p "$ART_DIR"

if [[ ! -x "$BIN" ]]; then
  OUT="$BIN" CUDA_ARCH_FLAGS=${CUDA_ARCH_FLAGS:-} bash scripts/build_src_mpcd_cuda_0208.sh
fi
if [[ ! -x "$BIN" ]]; then
  echo "[0208-full-stack] ERROR: CUDA-enabled binary not found after build: $BIN" >&2
  exit 127
fi

OUT_CSV=${OUT_CSV:-$ART_DIR/cuda_tg_full_gpu_stack_0208.csv}
printf 'grid,mode,NX,NY,steps,batchSize,elapsed_s,wallTime,speedupWallBaselineOverMode,failed_metrics,compared_metrics,verdict,q6Iterations,q6DivAfterProjectedFluxRms,cellActiveCalls,cellTotalSeconds,cellUploadSeconds,cellKernelSeconds,cellDownloadSeconds,thermostatActiveCalls,thermostatTotalSeconds,thermostatUploadSeconds,thermostatKernelSeconds,thermostatDownloadSeconds,cudaTimingSolves,cudaTimingIterations,cudaTimingBatches,cudaTimingConvergenceDownloads,cudaTimingTotalSeconds,cudaTimingHostReductionSeconds,cudaTimingApplyOperatorSeconds,runRoot,compareCsv,compareSummary\n' > "$OUT_CSV"

mode_flags() {
  local mode=$1
  case "$mode" in
    cpu_baseline)         echo "cpu 0 0" ;;
    cell_cuda)            echo "cpu 1 0" ;;
    thermostat_cuda)      echo "cpu 0 1" ;;
    cell_thermostat_cuda) echo "cpu 1 1" ;;
    q6_cuda)              echo "cuda 0 0" ;;
    q6_cell_cuda)         echo "cuda 1 0" ;;
    q6_thermostat_cuda)   echo "cuda 0 1" ;;
    full_cuda)            echo "cuda 1 1" ;;
    *) echo "[0208-full-stack] unknown mode '$mode'" >&2; return 2 ;;
  esac
}

run_validation() {
  local nx=$1 ny=$2 steps=$3 root=$4 tag=$5 projection=$6 cell_use=$7 thermo_use=$8
  local summary_every=${SUMMARY_EVERY_OVERRIDE:-$SUMMARY_EVERY_DEFAULT}
  local seed=$((SEED_BASE + nx + steps))
  env BIN="$BIN" BUILD_IF_MISSING=0 CASE_LIST="$CASE_LIST" \
      NX="$nx" NY="$ny" GAMMA="$GAMMA" STEPS="$steps" SUMMARY_EVERY="$summary_every" \
      THREADS="$THREADS" SEED="$seed" DUMP_STATE_EVERY=0 \
      RUN_ROOT="$root" RUN_TAG="$tag" PROJECTION_BACKEND="$projection" \
      MPCD_CUDA_CELL_MOMENTS_USE="$cell_use" \
      MPCD_CUDA_CELL_MOMENTS_SHADOW=0 \
      MPCD_CUDA_CELL_MOMENTS_REUSE_BUFFERS=${MPCD_CUDA_CELL_MOMENTS_REUSE_BUFFERS:-1} \
      MPCD_CUDA_CELL_MOMENTS_ALL_FLUID_FASTPATH=${MPCD_CUDA_CELL_MOMENTS_ALL_FLUID_FASTPATH:-1} \
      MPCD_CUDA_CELL_MOMENTS_UNIFORM_MASS_FASTPATH=${MPCD_CUDA_CELL_MOMENTS_UNIFORM_MASS_FASTPATH:-1} \
      MPCD_CUDA_THERMOSTAT_USE="$thermo_use" \
      MPCD_CUDA_THERMOSTAT_SHADOW=0 \
      MPCD_CUDA_THERMOSTAT_THREADS_PER_BLOCK=${MPCD_CUDA_THERMOSTAT_THREADS_PER_BLOCK:-256} \
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
fieldnames = ['grid','mode','NX','NY','steps','batchSize','elapsed_s','wallTime','speedupWallBaselineOverMode','failed_metrics','compared_metrics','verdict','q6Iterations','q6DivAfterProjectedFluxRms','cellActiveCalls','cellTotalSeconds','cellUploadSeconds','cellKernelSeconds','cellDownloadSeconds','thermostatActiveCalls','thermostatTotalSeconds','thermostatUploadSeconds','thermostatKernelSeconds','thermostatDownloadSeconds','cudaTimingSolves','cudaTimingIterations','cudaTimingBatches','cudaTimingConvergenceDownloads','cudaTimingTotalSeconds','cudaTimingHostReductionSeconds','cudaTimingApplyOperatorSeconds','runRoot','compareCsv','compareSummary']

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
if mode in ('q6_cuda','q6_cell_cuda','q6_thermostat_cuda','full_cuda') and (not math.isfinite(q6_div) or q6_div > div_max):
    verdict = 'FAIL'
    failed = max(failed, 1)

def sum_cuda_csv(path, columns, kernel_cols=None):
    out = {k: 0.0 for k in columns}
    out['calls'] = 0
    if path and os.path.exists(path):
        with open(path, newline='') as fp:
            rows = list(csv.DictReader(fp))
        out['calls'] = len(rows)
        for r in rows:
            for k in columns:
                try: out[k] += float(r.get(k, '0') or 0.0)
                except Exception: pass
    if kernel_cols:
        out['kernelSeconds'] = sum(out.get(k, 0.0) for k in kernel_cols)
    return out

cell_csv = os.path.join(root, case_name, 'cuda_cell_moments_active_0202.csv')
cell = sum_cuda_csv(cell_csv, ['totalSeconds','uploadSeconds','kernelSeconds','downloadSeconds'])
thermo_csv = os.path.join(root, case_name, 'cuda_cell_thermostat_active_0207.csv')
thermo = sum_cuda_csv(thermo_csv, ['totalSeconds','uploadSeconds','kineticKernelSeconds','scaleKernelSeconds','applyKernelSeconds','downloadSeconds'], ['kineticKernelSeconds','scaleKernelSeconds','applyKernelSeconds'])

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
    'batchSize': batch_size if mode in ('q6_cuda','q6_cell_cuda','q6_thermostat_cuda','full_cuda') else 0,
    'elapsed_s': f(sumr, 'elapsed_s'),
    'wallTime': wall,
    'speedupWallBaselineOverMode': base_wall / wall if wall > 0 else float('nan'),
    'failed_metrics': failed,
    'compared_metrics': compared,
    'verdict': verdict,
    'q6Iterations': i(sumr, 'q6Iterations'),
    'q6DivAfterProjectedFluxRms': q6_div,
    'cellActiveCalls': cell['calls'],
    'cellTotalSeconds': cell['totalSeconds'],
    'cellUploadSeconds': cell['uploadSeconds'],
    'cellKernelSeconds': cell['kernelSeconds'],
    'cellDownloadSeconds': cell['downloadSeconds'],
    'thermostatActiveCalls': thermo['calls'],
    'thermostatTotalSeconds': thermo['totalSeconds'],
    'thermostatUploadSeconds': thermo['uploadSeconds'],
    'thermostatKernelSeconds': thermo['kernelSeconds'],
    'thermostatDownloadSeconds': thermo['downloadSeconds'],
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
print(f"[0208-full-stack] {verdict} {label}/{mode}: wall={wall:.6g}s baselineSpeed={row['speedupWallBaselineOverMode']:.3f} failed={failed}/{compared} cell={row['cellTotalSeconds']:.3g}s thermo={row['thermostatTotalSeconds']:.3g}s q6={row['cudaTimingTotalSeconds']:.3g}s")
PY
}

run_and_record() {
  local label=$1 mode=$2 nx=$3 ny=$4 steps=$5 base_root=$6
  read -r projection cell_use thermo_use < <(mode_flags "$mode")
  local root="runs/cuda_tg_full_gpu_stack_0208_${mode}_${label}"
  local tag="cuda0208_${mode}_${label}"
  echo "[0208-full-stack] running $label/$mode projection=$projection cell=$cell_use thermo=$thermo_use"
  run_validation "$nx" "$ny" "$steps" "$root" "$tag" "$projection" "$cell_use" "$thermo_use"
  local compare_csv="none" compare_summary="none"
  if [[ "$mode" != "cpu_baseline" ]]; then
    local prefix="cuda_tg_full_gpu_stack_compare_0208_${mode}_${label}"
    compare_csv="$ART_DIR/${prefix}.csv"
    compare_summary="$ART_DIR/${prefix}_summary.csv"
    compare_to_baseline "$base_root" "$root" "$prefix" || true
  fi
  append_mode_row "$label" "$mode" "$nx" "$ny" "$steps" "$root" \
    "$base_root/validation_summary_0162.csv" "$root/validation_summary_0162.csv" "$compare_csv" "$compare_summary"

  if [[ "$mode" != "cpu_baseline" && "$STOP_ON_FAIL" == "1" ]]; then
    python3 - "$compare_summary" <<'PY'
import csv, sys, os
p=sys.argv[1]
if not os.path.exists(p):
    raise SystemExit(1)
with open(p, newline='') as f:
    rows=list(csv.DictReader(f))
failed=int(round(float(rows[0].get('failed_metrics','999999'))))
raise SystemExit(0 if failed == 0 else 1)
PY
  fi
}

for spec in $GRID_CASES; do
  IFS=: read -r nx steps <<< "$spec"
  if [[ -z "${nx:-}" || -z "${steps:-}" ]]; then
    echo "[0208-full-stack] invalid GRID_CASES entry '$spec' (expected NX:steps)" >&2
    exit 2
  fi
  ny=${NY_OVERRIDE:-$nx}
  label="${nx}x${ny}_s${steps}"

  # Ensure the baseline is run first and exactly once for this grid.
  base_root="runs/cuda_tg_full_gpu_stack_0208_cpu_baseline_${label}"
  base_done=0
  for mode in $MODES; do
    if [[ "$mode" == "cpu_baseline" ]]; then
      run_and_record "$label" "$mode" "$nx" "$ny" "$steps" "$base_root"
      base_done=1
      break
    fi
  done
  if [[ "$base_done" != "1" ]]; then
    run_and_record "$label" "cpu_baseline" "$nx" "$ny" "$steps" "$base_root"
  fi

  for mode in $MODES; do
    [[ "$mode" == "cpu_baseline" ]] && continue
    run_and_record "$label" "$mode" "$nx" "$ny" "$steps" "$base_root"
  done
done

echo "[0208-full-stack] wrote $OUT_CSV"
