#!/usr/bin/env bash
set -euo pipefail

# 0207 — validate active CUDA cell-relative thermostat inside the real SRC/MPCD step.
# CPU baseline drives one run; CUDA thermostat drives the optimized run. Q6 backend
# defaults to CPU to isolate the thermostat unless PROJECTION_BACKEND is changed.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BIN=${BIN:-build/src_mpcd_base_cuda_0207}
ART_DIR=${ART_DIR:-dev_history/artifacts/gpu_cuda_thermostat_0207}
GRID_CASES=${GRID_CASES:-"64:200 128:100"}
GAMMA=${GAMMA:-20}
THREADS=${THREADS:-8}
SUMMARY_EVERY_DEFAULT=${SUMMARY_EVERY:-50}
SEED_BASE=${SEED_BASE:-1620207}
PROJECTION_BACKEND=${PROJECTION_BACKEND:-cpu}
CASE_LIST=${CASE_LIST:-tg_periodic_full}
RUN_BASELINE=${RUN_BASELINE:-1}

mkdir -p "$ART_DIR"

if [[ ! -x "$BIN" ]]; then
  OUT="$BIN" CUDA_ARCH_FLAGS=${CUDA_ARCH_FLAGS:-} bash scripts/build_src_mpcd_cuda_0207.sh
fi
if [[ ! -x "$BIN" ]]; then
  echo "[0207-thermostat-active] ERROR: CUDA-enabled binary not found after build: $BIN" >&2
  exit 127
fi

OUT_CSV=${OUT_CSV:-$ART_DIR/cuda_cell_thermostat_active_0207.csv}
printf 'grid,NX,NY,steps,case,baselineElapsed_s,activeElapsed_s,baselineWallTime,activeWallTime,elapsedDelta_s,wallDelta_s,activeCalls,particlesVisitedPerCall,fluidParticlesPerCall,numCells,totalActiveSeconds,uploadSeconds,kineticKernelSeconds,scaleKernelSeconds,applyKernelSeconds,downloadSeconds,avgActiveTotalSeconds,avgKernelSeconds,cellsRescaled,particlesRescaled,kBTBefore,kBTAfter,scaleMean,scaleMin,scaleMax,failed_metrics,compared_metrics,verdict,activeCsv,compareCsv,compareSummary\n' > "$OUT_CSV"

read_elapsed() {
  python3 - "$1" <<'PY'
import csv, sys
with open(sys.argv[1], newline='') as f:
    rows=list(csv.DictReader(f))
print(rows[0].get('elapsed_s', 'nan'))
PY
}

append_active_summary() {
  local label=$1 nx=$2 ny=$3 steps=$4 case_name=$5 baseline_summary=$6 active_summary=$7 active_csv=$8 compare_csv=$9 compare_summary=${10} baseline_elapsed=${11} active_elapsed=${12}
  python3 - "$label" "$nx" "$ny" "$steps" "$case_name" "$baseline_summary" "$active_summary" "$active_csv" "$compare_csv" "$compare_summary" "$baseline_elapsed" "$active_elapsed" "$OUT_CSV" <<'PY'
import csv, sys
(label, nx, ny, steps, case_name, baseline_summary, active_summary, active_csv, compare_csv, compare_summary, baseline_elapsed_s, active_elapsed_s, out_csv) = sys.argv[1:14]

def read_one(path):
    with open(path, newline='') as f:
        rows=list(csv.DictReader(f))
    if len(rows) != 1:
        raise SystemExit(f"expected one row in {path}, got {len(rows)}")
    return rows[0]

def f(row, key, fallback='nan'):
    try: return float(row.get(key, fallback))
    except Exception: return float('nan')

def i(row, key, fallback='0'):
    try: return int(round(float(row.get(key, fallback))))
    except Exception: return 0

base = read_one(baseline_summary)
active = read_one(active_summary)
compare = read_one(compare_summary)
with open(active_csv, newline='') as fp:
    rows=list(csv.DictReader(fp))
if not rows:
    raise SystemExit(f"empty CUDA thermostat active CSV: {active_csv}")

def vals(key):
    out=[]
    for r in rows:
        try: out.append(float(r.get(key, 'nan')))
        except Exception: out.append(float('nan'))
    return out

def last(key):
    try: return float(rows[-1].get(key, 'nan'))
    except Exception: return float('nan')

calls=len(rows)
base_elapsed=float(baseline_elapsed_s)
active_elapsed=float(active_elapsed_s)
base_wall=f(base,'wallTime')
active_wall=f(active,'wallTime')
failed=i(compare,'failed_metrics','999999')
compared=i(compare,'compared_metrics','0')
verdict='PASS' if failed==0 else 'FAIL'
kin=sum(vals('kineticKernelSeconds'))
scale=sum(vals('scaleKernelSeconds'))
apply=sum(vals('applyKernelSeconds'))
row={
    'grid': label,
    'NX': nx,
    'NY': ny,
    'steps': steps,
    'case': case_name,
    'baselineElapsed_s': base_elapsed,
    'activeElapsed_s': active_elapsed,
    'baselineWallTime': base_wall,
    'activeWallTime': active_wall,
    'elapsedDelta_s': active_elapsed-base_elapsed,
    'wallDelta_s': active_wall-base_wall,
    'activeCalls': calls,
    'particlesVisitedPerCall': last('particlesVisited'),
    'fluidParticlesPerCall': last('fluidParticles'),
    'numCells': last('numCells'),
    'totalActiveSeconds': sum(vals('totalSeconds')),
    'uploadSeconds': sum(vals('uploadSeconds')),
    'kineticKernelSeconds': kin,
    'scaleKernelSeconds': scale,
    'applyKernelSeconds': apply,
    'downloadSeconds': sum(vals('downloadSeconds')),
    'avgActiveTotalSeconds': sum(vals('totalSeconds'))/calls,
    'avgKernelSeconds': (kin+scale+apply)/calls,
    'cellsRescaled': last('cellsRescaled'),
    'particlesRescaled': last('particlesRescaled'),
    'kBTBefore': last('kBTBefore'),
    'kBTAfter': last('kBTAfter'),
    'scaleMean': last('scaleMean'),
    'scaleMin': last('scaleMin'),
    'scaleMax': last('scaleMax'),
    'failed_metrics': failed,
    'compared_metrics': compared,
    'verdict': verdict,
    'activeCsv': active_csv,
    'compareCsv': compare_csv,
    'compareSummary': compare_summary,
}
fieldnames=['grid','NX','NY','steps','case','baselineElapsed_s','activeElapsed_s','baselineWallTime','activeWallTime','elapsedDelta_s','wallDelta_s','activeCalls','particlesVisitedPerCall','fluidParticlesPerCall','numCells','totalActiveSeconds','uploadSeconds','kineticKernelSeconds','scaleKernelSeconds','applyKernelSeconds','downloadSeconds','avgActiveTotalSeconds','avgKernelSeconds','cellsRescaled','particlesRescaled','kBTBefore','kBTAfter','scaleMean','scaleMin','scaleMax','failed_metrics','compared_metrics','verdict','activeCsv','compareCsv','compareSummary']
with open(out_csv, 'a', newline='') as fcsv:
    writer=csv.DictWriter(fcsv, fieldnames=fieldnames)
    writer.writerow(row)
print(f"[0207-thermostat-active] {verdict} {label}/{case_name}: activeWall={active_wall:.6g}s baselineWall={base_wall:.6g}s totalActive={row['totalActiveSeconds']:.6g}s kernels={kin+scale+apply:.6g}s failed={failed}/{compared}")
if verdict != 'PASS':
    raise SystemExit(1)
PY
}

run_one() {
  local nx=$1 steps=$2 ny=${NY_OVERRIDE:-$nx}
  local label="${nx}x${ny}_s${steps}"
  local seed=$((SEED_BASE + nx + steps))
  local summary_every=${SUMMARY_EVERY_OVERRIDE:-$SUMMARY_EVERY_DEFAULT}
  local base_root="runs/cuda_cell_thermostat_active_0207_baseline_${label}"
  local active_root="runs/cuda_cell_thermostat_active_0207_${label}"

  if [[ "$RUN_BASELINE" != "1" ]]; then
    echo "[0207-thermostat-active] ERROR: RUN_BASELINE=0 is not supported for this harness" >&2
    exit 4
  fi

  echo "[0207-thermostat-active] baseline $label"
  env BIN="$BIN" BUILD_IF_MISSING=0 CASE_LIST="$CASE_LIST" \
      NX="$nx" NY="$ny" GAMMA="$GAMMA" STEPS="$steps" SUMMARY_EVERY="$summary_every" \
      THREADS="$THREADS" SEED="$seed" DUMP_STATE_EVERY=0 \
      RUN_ROOT="$base_root" RUN_TAG="cuda0207_baseline_${label}" PROJECTION_BACKEND="$PROJECTION_BACKEND" \
      MPCD_CUDA_CELL_MOMENTS_USE=${MPCD_CUDA_CELL_MOMENTS_USE:-0} \
      MPCD_CUDA_CELL_MOMENTS_SHADOW=0 \
      MPCD_CUDA_THERMOSTAT_USE=0 \
      MPCD_CUDA_THERMOSTAT_SHADOW=0 \
      bash scripts/run_validation_mono_config_0162.sh
  local base_summary="$base_root/validation_summary_0162.csv"
  local base_elapsed
  base_elapsed=$(read_elapsed "$base_summary")

  echo "[0207-thermostat-active] active $label"
  env BIN="$BIN" BUILD_IF_MISSING=0 CASE_LIST="$CASE_LIST" \
      NX="$nx" NY="$ny" GAMMA="$GAMMA" STEPS="$steps" SUMMARY_EVERY="$summary_every" \
      THREADS="$THREADS" SEED="$seed" DUMP_STATE_EVERY=0 \
      RUN_ROOT="$active_root" RUN_TAG="cuda0207_active_${label}" PROJECTION_BACKEND="$PROJECTION_BACKEND" \
      MPCD_CUDA_CELL_MOMENTS_USE=${MPCD_CUDA_CELL_MOMENTS_USE:-0} \
      MPCD_CUDA_CELL_MOMENTS_SHADOW=0 \
      MPCD_CUDA_THERMOSTAT_USE=1 \
      MPCD_CUDA_THERMOSTAT_SHADOW=0 \
      MPCD_CUDA_THERMOSTAT_THREADS_PER_BLOCK=${MPCD_CUDA_THERMOSTAT_THREADS_PER_BLOCK:-256} \
      bash scripts/run_validation_mono_config_0162.sh
  local active_summary="$active_root/validation_summary_0162.csv"
  local active_elapsed
  active_elapsed=$(read_elapsed "$active_summary")

  local compare_csv="$ART_DIR/cuda_cell_thermostat_active_compare_0207_${label}.csv"
  local compare_summary="$ART_DIR/cuda_cell_thermostat_active_compare_summary_0207_${label}.csv"
  python3 scripts/compare_validation_mono_config_0162.py \
    --origin "$base_root" \
    --optimized "$active_root" \
    --out "$compare_csv" \
    --summary-out "$compare_summary"

  local case_name
  for case_name in $CASE_LIST; do
    local active_csv="$active_root/$case_name/cuda_cell_thermostat_active_0207.csv"
    if [[ ! -f "$active_csv" ]]; then
      echo "[0207-thermostat-active] ERROR: missing $active_csv" >&2
      exit 3
    fi
    append_active_summary "$label" "$nx" "$ny" "$steps" "$case_name" \
      "$base_summary" "$active_summary" "$active_csv" "$compare_csv" "$compare_summary" \
      "$base_elapsed" "$active_elapsed"
  done
}

for spec in $GRID_CASES; do
  IFS=: read -r nx steps <<< "$spec"
  if [[ -z "${nx:-}" || -z "${steps:-}" ]]; then
    echo "[0207-thermostat-active] invalid GRID_CASES entry '$spec' (expected NX:steps)" >&2
    exit 2
  fi
  run_one "$nx" "$steps"
done

echo "[0207-thermostat-active] wrote $OUT_CSV"
