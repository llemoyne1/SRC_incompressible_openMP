#!/usr/bin/env bash
set -euo pipefail

# 0215 — validate persistent-particle CUDA deposit->SRC collision->thermostat substep.
# This path replaces collision and the cell-relative thermostat for a strict no-Q6/no-capacity subset.
# The later thermostat phase consumes diagnostics recorded by the persistent CUDA substep.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BIN=${BIN:-build/src_mpcd_base_cuda_0215}
ART_DIR=${ART_DIR:-dev_history/artifacts/gpu_cuda_persistent_0215}
GRID_CASES=${GRID_CASES:-"64:200 128:100"}
GAMMA=${GAMMA:-20}
THREADS=${THREADS:-8}
SUMMARY_EVERY_DEFAULT=${SUMMARY_EVERY:-50}
SEED_BASE=${SEED_BASE:-1620215}
PROJECTION_BACKEND=${PROJECTION_BACKEND:-cpu}
PROJECTION_ENABLE=${PROJECTION_ENABLE:-false}
CASE_LIST=${CASE_LIST:-tg_periodic_full}
RUN_BASELINE=${RUN_BASELINE:-1}

mkdir -p "$ART_DIR"

if [[ ! -x "$BIN" ]]; then
  OUT="$BIN" CUDA_ARCH_FLAGS=${CUDA_ARCH_FLAGS:-} bash scripts/build_src_mpcd_cuda_0215.sh
fi
if [[ ! -x "$BIN" ]]; then
  echo "[0215-persistent-src-thermostat] ERROR: CUDA-enabled binary not found after build: $BIN" >&2
  exit 127
fi

OUT_CSV=${OUT_CSV:-$ART_DIR/cuda_persistent_src_collision_thermostat_0215.csv}
printf 'grid,NX,NY,steps,case,baselineElapsed_s,activeElapsed_s,baselineWallTime,activeWallTime,elapsedDelta_s,wallDelta_s,activeCalls,particlesVisitedPerCall,fluidParticlesPerCall,particlesRotatedPerCall,invalidCellParticles,numCells,totalActiveSeconds,uploadSeconds,kernelSeconds,downloadSeconds,avgActiveTotalSeconds,avgKernelSeconds,thermostatAppliedCalls,thermostatCellsRescaledLast,thermostatParticlesRescaledLast,thermostatKBTBeforeLast,thermostatKBTAfterLast,failed_metrics,compared_metrics,verdict,activeCsv,compareCsv,compareSummary\n' > "$OUT_CSV"

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
import csv, sys, math
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
    raise SystemExit(f"empty CUDA persistent active CSV: {active_csv}")

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
invalid=sum(i(r,'invalidCellParticles','0') for r in rows)
verdict='PASS' if failed==0 and invalid==0 else 'FAIL'
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
    'particlesRotatedPerCall': last('particlesRotated'),
    'invalidCellParticles': invalid,
    'numCells': last('numCells'),
    'totalActiveSeconds': sum(vals('totalSeconds')),
    'uploadSeconds': sum(vals('uploadSeconds')),
    'kernelSeconds': sum(vals('kernelSeconds')),
    'downloadSeconds': sum(vals('downloadSeconds')),
    'avgActiveTotalSeconds': sum(vals('totalSeconds'))/calls,
    'avgKernelSeconds': sum(vals('kernelSeconds'))/calls,
    'thermostatAppliedCalls': sum(1 for r in rows if str(r.get('thermostatAppliedOnGpu','0')) not in ('0','0.0','')),
    'thermostatCellsRescaledLast': last('thermostatCellsRescaled'),
    'thermostatParticlesRescaledLast': last('thermostatParticlesRescaled'),
    'thermostatKBTBeforeLast': last('thermostatKBTBefore'),
    'thermostatKBTAfterLast': last('thermostatKBTAfter'),
    'failed_metrics': failed,
    'compared_metrics': compared,
    'verdict': verdict,
    'activeCsv': active_csv,
    'compareCsv': compare_csv,
    'compareSummary': compare_summary,
}
fieldnames=['grid','NX','NY','steps','case','baselineElapsed_s','activeElapsed_s','baselineWallTime','activeWallTime','elapsedDelta_s','wallDelta_s','activeCalls','particlesVisitedPerCall','fluidParticlesPerCall','particlesRotatedPerCall','invalidCellParticles','numCells','totalActiveSeconds','uploadSeconds','kernelSeconds','downloadSeconds','avgActiveTotalSeconds','avgKernelSeconds','thermostatAppliedCalls','thermostatCellsRescaledLast','thermostatParticlesRescaledLast','thermostatKBTBeforeLast','thermostatKBTAfterLast','failed_metrics','compared_metrics','verdict','activeCsv','compareCsv','compareSummary']
with open(out_csv, 'a', newline='') as fcsv:
    writer=csv.DictWriter(fcsv, fieldnames=fieldnames)
    writer.writerow(row)
print(f"[0215-persistent-src-thermostat] {verdict} {label}/{case_name}: activeWall={active_wall:.6g}s baselineWall={base_wall:.6g}s totalActive={row['totalActiveSeconds']:.6g}s kernel={row['kernelSeconds']:.6g}s thermostatCalls={row['thermostatAppliedCalls']} failed={failed}/{compared}")
if verdict != 'PASS':
    raise SystemExit(1)
PY
}

run_one() {
  local nx=$1 steps=$2 ny=${NY_OVERRIDE:-$nx}
  local label="${nx}x${ny}_s${steps}"
  local seed=$((SEED_BASE + nx + steps))
  local summary_every=${SUMMARY_EVERY_OVERRIDE:-$SUMMARY_EVERY_DEFAULT}
  local base_root="runs/cuda_persistent_src_thermostat_0215_baseline_${label}"
  local active_root="runs/cuda_persistent_src_thermostat_0215_active_${label}"

  if [[ "$RUN_BASELINE" != "1" ]]; then
    echo "[0215-persistent-src-thermostat] ERROR: RUN_BASELINE=0 is not supported for this harness" >&2
    exit 4
  fi

  echo "[0215-persistent-src-thermostat] baseline $label"
  env BIN="$BIN" BUILD_IF_MISSING=0 CASE_LIST="$CASE_LIST" \
      NX="$nx" NY="$ny" GAMMA="$GAMMA" STEPS="$steps" SUMMARY_EVERY="$summary_every" \
      THREADS="$THREADS" SEED="$seed" DUMP_STATE_EVERY=0 \
      RUN_ROOT="$base_root" RUN_TAG="cuda0215_baseline_${label}" PROJECTION_BACKEND="$PROJECTION_BACKEND" PROJECTION_ENABLE="$PROJECTION_ENABLE" \
      MPCD_CUDA_CELL_MOMENTS_USE=0 \
      MPCD_CUDA_THERMOSTAT_USE=0 \
      MPCD_CUDA_SRC_COLLISION_USE=0 \
      MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=0 \
      bash scripts/run_validation_mono_config_0162.sh
  local base_summary="$base_root/validation_summary_0162.csv"
  local base_elapsed
  base_elapsed=$(read_elapsed "$base_summary")

  echo "[0215-persistent-src-thermostat] active $label"
  env BIN="$BIN" BUILD_IF_MISSING=0 CASE_LIST="$CASE_LIST" \
      NX="$nx" NY="$ny" GAMMA="$GAMMA" STEPS="$steps" SUMMARY_EVERY="$summary_every" \
      THREADS="$THREADS" SEED="$seed" DUMP_STATE_EVERY=0 \
      RUN_ROOT="$active_root" RUN_TAG="cuda0215_persistent_src_thermostat_${label}" PROJECTION_BACKEND="$PROJECTION_BACKEND" PROJECTION_ENABLE="$PROJECTION_ENABLE" \
      MPCD_CUDA_CELL_MOMENTS_USE=0 \
      MPCD_CUDA_THERMOSTAT_USE=0 \
      MPCD_CUDA_SRC_COLLISION_USE=0 \
      MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=0 \
      MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE=1 \
      MPCD_CUDA_PERSISTENT_THREADS_PER_BLOCK=${MPCD_CUDA_PERSISTENT_THREADS_PER_BLOCK:-256} \
      bash scripts/run_validation_mono_config_0162.sh
  local active_summary="$active_root/validation_summary_0162.csv"
  local active_elapsed
  active_elapsed=$(read_elapsed "$active_summary")

  local compare_csv="$ART_DIR/cuda_persistent_src_collision_thermostat_compare_0215_${label}.csv"
  local compare_summary="$ART_DIR/cuda_persistent_src_collision_thermostat_compare_summary_0215_${label}.csv"
  python3 scripts/compare_validation_mono_config_0162.py \
    --origin "$base_root" \
    --optimized "$active_root" \
    --out "$compare_csv" \
    --summary-out "$compare_summary"

  local case_name
  for case_name in $CASE_LIST; do
    local active_csv="$active_root/$case_name/cuda_persistent_src_collision_thermostat_0215.csv"
    if [[ ! -f "$active_csv" ]]; then
      echo "[0215-persistent-src-thermostat] ERROR: missing $active_csv" >&2
      exit 3
    fi
    append_active_summary "$label" "$nx" "$ny" "$steps" "$case_name" \
      "$base_summary" "$active_summary" "$active_csv" "$compare_csv" "$compare_summary" \
      "$base_elapsed" "$active_elapsed"
  done
}

for item in $GRID_CASES; do
  IFS=':' read -r nx steps <<< "$item"
  if [[ -z "${nx:-}" || -z "${steps:-}" ]]; then
    echo "[0215-persistent-src-thermostat] malformed GRID_CASES entry: $item" >&2
    exit 2
  fi
  run_one "$nx" "$steps"
done

echo "[0215-persistent-src-thermostat] wrote $OUT_CSV"
