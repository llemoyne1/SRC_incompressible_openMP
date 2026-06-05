#!/usr/bin/env bash
set -euo pipefail

# 0201 — run active CUDA particle->cell deposit inside the real SRC/MPCD
# collision step. The CUDA path replaces the CPU thread-local deposit only when
# MPCD_CUDA_CELL_MOMENTS_USE=1 is set by this script. The rest of the collision
# step, virtual-particle wall augmentation, rotation, thermostat, resampling and
# projection remain unchanged.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BIN=${BIN:-build/src_mpcd_base_cuda_0201}
ART_DIR=${ART_DIR:-dev_history/artifacts/gpu_cuda_deposit_0201}
GRID_CASES=${GRID_CASES:-"64:200 128:100"}
GAMMA=${GAMMA:-20}
THREADS=${THREADS:-8}
SUMMARY_EVERY_DEFAULT=${SUMMARY_EVERY:-50}
SEED_BASE=${SEED_BASE:-1620201}
PROJECTION_BACKEND=${PROJECTION_BACKEND:-cpu}
CASE_LIST=${CASE_LIST:-tg_periodic_full}
RUN_BASELINE=${RUN_BASELINE:-1}
ACTIVE_TOL=${ACTIVE_TOL:-1e-9}

mkdir -p "$ART_DIR"

if [[ ! -x "$BIN" ]]; then
  OUT="$BIN" CUDA_ARCH_FLAGS=${CUDA_ARCH_FLAGS:-} bash scripts/build_src_mpcd_cuda_0201.sh
fi
if [[ ! -x "$BIN" ]]; then
  echo "[0201-cell-active] ERROR: CUDA-enabled binary not found after build: $BIN" >&2
  exit 127
fi

OUT_CSV=${OUT_CSV:-$ART_DIR/cuda_cell_moments_active_0201.csv}
printf 'grid,NX,NY,steps,case,mode,baselineElapsed_s,activeElapsed_s,baselineWallTime,activeWallTime,elapsedDelta_s,wallDelta_s,activeCalls,particlesVisitedPerCall,fluidParticlesPerCall,numCells,totalActiveSeconds,uploadSeconds,kernelSeconds,downloadSeconds,avgActiveTotalSeconds,avgKernelSeconds,failed_metrics,compared_metrics,verdict,activeCsv\n' > "$OUT_CSV"

append_active_summary() {
  local label=$1 nx=$2 ny=$3 steps=$4 case_name=$5 baseline_summary=$6 active_summary=$7 active_csv=$8 compare_summary=$9 baseline_elapsed=${10} active_elapsed=${11}
  python3 - "$label" "$nx" "$ny" "$steps" "$case_name" "$baseline_summary" "$active_summary" "$active_csv" "$compare_summary" "$baseline_elapsed" "$active_elapsed" "$ACTIVE_TOL" "$OUT_CSV" <<'PY'
import csv
import math
import sys

(label, nx, ny, steps, case_name, baseline_summary, active_summary, active_csv, compare_summary, baseline_elapsed_s, active_elapsed_s, active_tol, out_csv) = sys.argv[1:14]

def read_one(path):
    with open(path, newline='') as f:
        rows = list(csv.DictReader(f))
    if len(rows) != 1:
        raise SystemExit(f"expected one row in {path}, got {len(rows)}")
    return rows[0]

def f(row, key, fallback='nan'):
    try:
        return float(row.get(key, fallback))
    except Exception:
        return float('nan')

base = read_one(baseline_summary) if baseline_summary != 'none' else {}
active = read_one(active_summary)
compare = read_one(compare_summary)
with open(active_csv, newline='') as fp:
    rows = list(csv.DictReader(fp))
if not rows:
    raise SystemExit(f"empty CUDA active CSV: {active_csv}")

def sf(key):
    out = []
    for r in rows:
        try:
            out.append(float(r[key]))
        except Exception:
            out.append(float('nan'))
    return out

calls = len(rows)
particles = sf('particlesVisited')[0]
fluid = sf('fluidParticles')[0]
num_cells = sf('numCells')[0]
total_active = sum(sf('totalSeconds'))
upload = sum(sf('uploadSeconds'))
kernel = sum(sf('kernelSeconds'))
download = sum(sf('downloadSeconds'))
base_elapsed = float(baseline_elapsed_s) if baseline_elapsed_s != 'nan' else float('nan')
active_elapsed = float(active_elapsed_s)
base_wall = f(base, 'wallTime') if base else float('nan')
active_wall = f(active, 'wallTime')
failed = int(float(compare.get('failed_metrics', '999999')))
compared = int(float(compare.get('compared_metrics', '0')))
verdict = 'PASS' if failed == 0 else 'FAIL'
row = {
    'grid': label,
    'NX': nx,
    'NY': ny,
    'steps': steps,
    'case': case_name,
    'mode': 'active',
    'baselineElapsed_s': base_elapsed,
    'activeElapsed_s': active_elapsed,
    'baselineWallTime': base_wall,
    'activeWallTime': active_wall,
    'elapsedDelta_s': active_elapsed - base_elapsed if math.isfinite(base_elapsed) else float('nan'),
    'wallDelta_s': active_wall - base_wall if math.isfinite(base_wall) else float('nan'),
    'activeCalls': calls,
    'particlesVisitedPerCall': particles,
    'fluidParticlesPerCall': fluid,
    'numCells': num_cells,
    'totalActiveSeconds': total_active,
    'uploadSeconds': upload,
    'kernelSeconds': kernel,
    'downloadSeconds': download,
    'avgActiveTotalSeconds': total_active / calls,
    'avgKernelSeconds': kernel / calls,
    'failed_metrics': failed,
    'compared_metrics': compared,
    'verdict': verdict,
    'activeCsv': active_csv,
}
with open(out_csv, 'a', newline='') as fcsv:
    writer = csv.DictWriter(fcsv, fieldnames=list(row.keys()))
    writer.writerow(row)
print(f"[0201-cell-active] {verdict} {label}/{case_name}: activeWall={active_wall:.6g}s baselineWall={base_wall:.6g}s totalActive={total_active:.6g}s kernel={kernel:.6g}s failed={failed}/{compared}")
if verdict != 'PASS':
    raise SystemExit(1)
PY
}

read_elapsed() {
  python3 - "$1" <<'PY'
import csv, sys
with open(sys.argv[1], newline='') as f:
    rows=list(csv.DictReader(f))
print(rows[0]['elapsed_s'])
PY
}

run_one() {
  local nx=$1 steps=$2 ny=${NY_OVERRIDE:-$nx}
  local label="${nx}x${ny}_s${steps}"
  local seed=$((SEED_BASE + nx + steps))
  local summary_every=${SUMMARY_EVERY_OVERRIDE:-$SUMMARY_EVERY_DEFAULT}
  local base_root="runs/cuda_cell_moments_active_0201_baseline_${label}"
  local active_root="runs/cuda_cell_moments_active_0201_${label}"
  local base_summary="none"
  local base_elapsed="nan"

  if [[ "$RUN_BASELINE" == "1" ]]; then
    echo "[0201-cell-active] baseline $label"
    env BIN="$BIN" BUILD_IF_MISSING=0 CASE_LIST="$CASE_LIST" \
        NX="$nx" NY="$ny" GAMMA="$GAMMA" STEPS="$steps" SUMMARY_EVERY="$summary_every" \
        THREADS="$THREADS" SEED="$seed" DUMP_STATE_EVERY=0 \
        RUN_ROOT="$base_root" RUN_TAG="cuda0201_baseline_${label}" PROJECTION_BACKEND="$PROJECTION_BACKEND" \
        MPCD_CUDA_CELL_MOMENTS_USE=0 \
        MPCD_CUDA_CELL_MOMENTS_SHADOW=0 \
        bash scripts/run_validation_mono_config_0162.sh
    base_summary="$base_root/validation_summary_0162.csv"
    base_elapsed=$(read_elapsed "$base_summary")
  fi

  echo "[0201-cell-active] active $label"
  env BIN="$BIN" BUILD_IF_MISSING=0 CASE_LIST="$CASE_LIST" \
      NX="$nx" NY="$ny" GAMMA="$GAMMA" STEPS="$steps" SUMMARY_EVERY="$summary_every" \
      THREADS="$THREADS" SEED="$seed" DUMP_STATE_EVERY=0 \
      RUN_ROOT="$active_root" RUN_TAG="cuda0201_active_${label}" PROJECTION_BACKEND="$PROJECTION_BACKEND" \
      MPCD_CUDA_CELL_MOMENTS_USE=1 \
      MPCD_CUDA_CELL_MOMENTS_SHADOW=0 \
      bash scripts/run_validation_mono_config_0162.sh

  local active_summary="$active_root/validation_summary_0162.csv"
  local active_elapsed
  active_elapsed=$(read_elapsed "$active_summary")

  if [[ "$RUN_BASELINE" != "1" ]]; then
    echo "[0201-cell-active] ERROR: RUN_BASELINE=0 is not supported for comparison summary yet" >&2
    exit 4
  fi

  local compare_csv="$ART_DIR/cuda_cell_moments_active_compare_0201_${label}.csv"
  local compare_summary="$ART_DIR/cuda_cell_moments_active_compare_summary_0201_${label}.csv"
  python3 scripts/compare_validation_mono_config_0162.py \
    --origin "$base_root" \
    --optimized "$active_root" \
    --out "$compare_csv" \
    --summary-out "$compare_summary"

  local case_name
  for case_name in $CASE_LIST; do
    local active_csv="$active_root/$case_name/cuda_cell_moments_active_0201.csv"
    if [[ ! -f "$active_csv" ]]; then
      echo "[0201-cell-active] ERROR: missing $active_csv" >&2
      exit 3
    fi
    append_active_summary "$label" "$nx" "$ny" "$steps" "$case_name" "$base_summary" "$active_summary" "$active_csv" "$compare_summary" "$base_elapsed" "$active_elapsed"
  done
}

for spec in $GRID_CASES; do
  IFS=: read -r nx steps <<< "$spec"
  if [[ -z "${nx:-}" || -z "${steps:-}" ]]; then
    echo "[0201-cell-active] invalid GRID_CASES entry '$spec' (expected NX:steps)" >&2
    exit 2
  fi
  run_one "$nx" "$steps"
done

echo "[0201-cell-active] wrote $OUT_CSV"
