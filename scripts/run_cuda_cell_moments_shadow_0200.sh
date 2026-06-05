#!/usr/bin/env bash
set -euo pipefail

# 0200 — run CUDA cell-moments shadow validation inside the real SRC/MPCD step.
# The CPU deposit still drives the dynamics. CUDA recomputes particle->cell
# moments after the CPU thread-local deposit and before virtual-particle wall
# augmentation, then compares against the CPU real-particle aggregates.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BIN=${BIN:-build/src_mpcd_base_cuda_0200}
ART_DIR=${ART_DIR:-dev_history/artifacts/gpu_cuda_deposit_0200}
GRID_CASES=${GRID_CASES:-"64:200 128:100"}
GAMMA=${GAMMA:-20}
THREADS=${THREADS:-8}
SUMMARY_EVERY_DEFAULT=${SUMMARY_EVERY:-50}
SEED_BASE=${SEED_BASE:-1620200}
PROJECTION_BACKEND=${PROJECTION_BACKEND:-cpu}
CASE_LIST=${CASE_LIST:-tg_periodic_full}
RUN_BASELINE=${RUN_BASELINE:-1}
SHADOW_EVERY=${SHADOW_EVERY:-1}
SHADOW_TOL=${SHADOW_TOL:-1e-9}
SHADOW_STRICT=${SHADOW_STRICT:-1}

mkdir -p "$ART_DIR"

if [[ ! -x "$BIN" ]]; then
  OUT="$BIN" CUDA_ARCH_FLAGS=${CUDA_ARCH_FLAGS:-} bash scripts/build_src_mpcd_cuda_0200.sh
fi
if [[ ! -x "$BIN" ]]; then
  echo "[0200-cell-shadow] ERROR: CUDA-enabled binary not found after build: $BIN" >&2
  exit 127
fi

OUT_CSV=${OUT_CSV:-$ART_DIR/cuda_cell_moments_shadow_0200.csv}
printf 'grid,NX,NY,steps,case,mode,baselineElapsed_s,shadowElapsed_s,baselineWallTime,shadowWallTime,elapsedOverhead_s,wallOverhead_s,shadowCalls,shadowEvery,particlesVisitedPerCall,fluidParticlesPerCall,numCells,totalShadowSeconds,uploadSeconds,kernelSeconds,downloadSeconds,avgShadowTotalSeconds,avgKernelSeconds,cellIdMismatches,countMismatches,maxAbsMass,maxAbsPx,maxAbsPy,maxAbsUx,maxAbsUy,sumAbsMass,sumAbsPx,sumAbsPy,verdict,shadowCsv\n' > "$OUT_CSV"

append_shadow_summary() {
  local label=$1 nx=$2 ny=$3 steps=$4 case_name=$5 baseline_summary=$6 shadow_summary=$7 shadow_csv=$8 baseline_elapsed=$9 shadow_elapsed=${10}
  python3 - "$label" "$nx" "$ny" "$steps" "$case_name" "$baseline_summary" "$shadow_summary" "$shadow_csv" "$baseline_elapsed" "$shadow_elapsed" "$SHADOW_EVERY" "$OUT_CSV" <<'PY'
import csv
import math
import sys

(label, nx, ny, steps, case_name, baseline_summary, shadow_summary, shadow_csv, baseline_elapsed_s, shadow_elapsed_s, shadow_every, out_csv) = sys.argv[1:13]

def read_summary(path):
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

base = read_summary(baseline_summary) if baseline_summary != 'none' else {}
shadow = read_summary(shadow_summary)
with open(shadow_csv, newline='') as fp:
    rows = list(csv.DictReader(fp))
if not rows:
    raise SystemExit(f"empty CUDA shadow CSV: {shadow_csv}")

def sf(key):
    vals = []
    for r in rows:
        try:
            vals.append(float(r[key]))
        except Exception:
            vals.append(float('nan'))
    return vals

def si(key):
    vals = []
    for r in rows:
        try:
            vals.append(int(float(r[key])))
        except Exception:
            vals.append(0)
    return vals

calls = len(rows)
cell_id = sum(si('cellIdMismatches'))
count_mis = sum(si('countMismatches'))
max_abs_mass = max(sf('maxAbsMass'))
max_abs_px = max(sf('maxAbsPx'))
max_abs_py = max(sf('maxAbsPy'))
max_abs_ux = max(sf('maxAbsUx'))
max_abs_uy = max(sf('maxAbsUy'))
total_shadow = sum(sf('totalSeconds'))
upload = sum(sf('uploadSeconds'))
kernel = sum(sf('kernelSeconds'))
download = sum(sf('downloadSeconds'))
particles = sf('particlesVisited')[0]
fluid = sf('fluidParticles')[0]
num_cells = sf('numCells')[0]
sum_abs_mass = sum(sf('sumAbsMass'))
sum_abs_px = sum(sf('sumAbsPx'))
sum_abs_py = sum(sf('sumAbsPy'))
base_elapsed = float(baseline_elapsed_s) if baseline_elapsed_s != 'nan' else float('nan')
shadow_elapsed = float(shadow_elapsed_s)
base_wall = f(base, 'wallTime') if base else float('nan')
shadow_wall = f(shadow, 'wallTime')
verdict = 'PASS' if cell_id == 0 and count_mis == 0 and max(max_abs_mass, max_abs_px, max_abs_py, max_abs_ux, max_abs_uy) <= 1.0e-9 else 'FAIL'
row = {
    'grid': label,
    'NX': nx,
    'NY': ny,
    'steps': steps,
    'case': case_name,
    'mode': 'shadow',
    'baselineElapsed_s': base_elapsed,
    'shadowElapsed_s': shadow_elapsed,
    'baselineWallTime': base_wall,
    'shadowWallTime': shadow_wall,
    'elapsedOverhead_s': shadow_elapsed - base_elapsed if math.isfinite(base_elapsed) else float('nan'),
    'wallOverhead_s': shadow_wall - base_wall if math.isfinite(base_wall) else float('nan'),
    'shadowCalls': calls,
    'shadowEvery': shadow_every,
    'particlesVisitedPerCall': particles,
    'fluidParticlesPerCall': fluid,
    'numCells': num_cells,
    'totalShadowSeconds': total_shadow,
    'uploadSeconds': upload,
    'kernelSeconds': kernel,
    'downloadSeconds': download,
    'avgShadowTotalSeconds': total_shadow / calls,
    'avgKernelSeconds': kernel / calls,
    'cellIdMismatches': cell_id,
    'countMismatches': count_mis,
    'maxAbsMass': max_abs_mass,
    'maxAbsPx': max_abs_px,
    'maxAbsPy': max_abs_py,
    'maxAbsUx': max_abs_ux,
    'maxAbsUy': max_abs_uy,
    'sumAbsMass': sum_abs_mass,
    'sumAbsPx': sum_abs_px,
    'sumAbsPy': sum_abs_py,
    'verdict': verdict,
    'shadowCsv': shadow_csv,
}
with open(out_csv, 'a', newline='') as fcsv:
    writer = csv.DictWriter(fcsv, fieldnames=list(row.keys()))
    writer.writerow(row)
print(f"[0200-cell-shadow] {verdict} {label}/{case_name}: calls={calls} kernel={kernel:.6g}s upload={upload:.6g}s totalShadow={total_shadow:.6g}s maxAbsMass={max_abs_mass:.3e} maxAbsPx={max_abs_px:.3e} maxAbsPy={max_abs_py:.3e}")
if verdict != 'PASS':
    raise SystemExit(1)
PY
}

run_one() {
  local nx=$1 steps=$2 ny=${NY_OVERRIDE:-$nx}
  local label="${nx}x${ny}_s${steps}"
  local seed=$((SEED_BASE + nx + steps))
  local summary_every=${SUMMARY_EVERY_OVERRIDE:-$SUMMARY_EVERY_DEFAULT}
  local base_root="runs/cuda_cell_moments_shadow_0200_baseline_${label}"
  local shadow_root="runs/cuda_cell_moments_shadow_0200_${label}"
  local base_summary="none"
  local base_elapsed="nan"

  if [[ "$RUN_BASELINE" == "1" ]]; then
    echo "[0200-cell-shadow] baseline $label"
    env BIN="$BIN" BUILD_IF_MISSING=0 CASE_LIST="$CASE_LIST" \
        NX="$nx" NY="$ny" GAMMA="$GAMMA" STEPS="$steps" SUMMARY_EVERY="$summary_every" \
        THREADS="$THREADS" SEED="$seed" DUMP_STATE_EVERY=0 \
        RUN_ROOT="$base_root" RUN_TAG="cuda0200_baseline_${label}" PROJECTION_BACKEND="$PROJECTION_BACKEND" \
        MPCD_CUDA_CELL_MOMENTS_SHADOW=0 \
        bash scripts/run_validation_mono_config_0162.sh
    base_summary="$base_root/validation_summary_0162.csv"
    base_elapsed=$(python3 - "$base_summary" <<'PY'
import csv, sys
with open(sys.argv[1], newline='') as f:
    rows=list(csv.DictReader(f))
print(rows[0]['elapsed_s'])
PY
)
  fi

  echo "[0200-cell-shadow] shadow $label"
  env BIN="$BIN" BUILD_IF_MISSING=0 CASE_LIST="$CASE_LIST" \
      NX="$nx" NY="$ny" GAMMA="$GAMMA" STEPS="$steps" SUMMARY_EVERY="$summary_every" \
      THREADS="$THREADS" SEED="$seed" DUMP_STATE_EVERY=0 \
      RUN_ROOT="$shadow_root" RUN_TAG="cuda0200_shadow_${label}" PROJECTION_BACKEND="$PROJECTION_BACKEND" \
      MPCD_CUDA_CELL_MOMENTS_SHADOW=1 \
      MPCD_CUDA_CELL_MOMENTS_SHADOW_EVERY="$SHADOW_EVERY" \
      MPCD_CUDA_CELL_MOMENTS_SHADOW_TOL="$SHADOW_TOL" \
      MPCD_CUDA_CELL_MOMENTS_SHADOW_STRICT="$SHADOW_STRICT" \
      bash scripts/run_validation_mono_config_0162.sh

  local shadow_summary="$shadow_root/validation_summary_0162.csv"
  local case_name
  for case_name in $CASE_LIST; do
    local shadow_csv="$shadow_root/$case_name/cuda_cell_moments_shadow_0200.csv"
    if [[ ! -f "$shadow_csv" ]]; then
      echo "[0200-cell-shadow] ERROR: missing $shadow_csv" >&2
      exit 3
    fi
    append_shadow_summary "$label" "$nx" "$ny" "$steps" "$case_name" "$base_summary" "$shadow_summary" "$shadow_csv" "$base_elapsed" \
      "$(python3 - "$shadow_summary" <<'PY'
import csv, sys
with open(sys.argv[1], newline='') as f:
    rows=list(csv.DictReader(f))
print(rows[0]['elapsed_s'])
PY
)"
  done

  if [[ "$RUN_BASELINE" == "1" ]]; then
    python3 scripts/compare_validation_mono_config_0162.py \
      --origin "$base_root" \
      --optimized "$shadow_root" \
      --out "$ART_DIR/cuda_cell_moments_shadow_compare_0200_${label}.csv" \
      --summary-out "$ART_DIR/cuda_cell_moments_shadow_compare_summary_0200_${label}.csv"
  fi
}

for spec in $GRID_CASES; do
  IFS=: read -r nx steps <<< "$spec"
  if [[ -z "${nx:-}" || -z "${steps:-}" ]]; then
    echo "[0200-cell-shadow] invalid GRID_CASES entry '$spec' (expected NX:steps)" >&2
    exit 2
  fi
  run_one "$nx" "$steps"
done

echo "[0200-cell-shadow] wrote $OUT_CSV"
