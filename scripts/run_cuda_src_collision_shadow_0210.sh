#!/usr/bin/env bash
set -euo pipefail

# 0210 — run CUDA SRC collision in shadow mode inside the real SRC/MPCD step.
# The CPU collision remains active; CUDA applies the same rotation to a copied
# pre-collision state and compares post-collision velocities.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BIN=${BIN:-build/src_mpcd_base_cuda_0210}
ART_DIR=${ART_DIR:-dev_history/artifacts/gpu_cuda_collision_0210}
GRID_CASES=${GRID_CASES:-"64:200 128:100"}
GAMMA=${GAMMA:-20}
THREADS=${THREADS:-8}
SUMMARY_EVERY_DEFAULT=${SUMMARY_EVERY:-50}
SEED_BASE=${SEED_BASE:-1620210}
PROJECTION_BACKEND=${PROJECTION_BACKEND:-cpu}
CASE_LIST=${CASE_LIST:-tg_periodic_full}
SHADOW_TOL=${SHADOW_TOL:-1e-12}
RUN_BASELINE=${RUN_BASELINE:-1}

mkdir -p "$ART_DIR"

if [[ ! -x "$BIN" ]]; then
  OUT="$BIN" CUDA_ARCH_FLAGS=${CUDA_ARCH_FLAGS:-} bash scripts/build_src_mpcd_cuda_0210.sh
fi
if [[ ! -x "$BIN" ]]; then
  echo "[0210-src-shadow] ERROR: CUDA-enabled binary not found after build: $BIN" >&2
  exit 127
fi

OUT_CSV=${OUT_CSV:-$ART_DIR/cuda_src_collision_shadow_0210.csv}
printf 'grid,NX,NY,steps,case,baselineElapsed_s,shadowElapsed_s,baselineWallTime,shadowWallTime,elapsedDelta_s,wallDelta_s,shadowCalls,particlesVisitedPerCall,particlesRotatedPerCall,invalidCellParticles,numCells,totalShadowSeconds,uploadSeconds,kernelSeconds,downloadSeconds,avgShadowTotalSeconds,avgKernelSeconds,maxAbsVx,maxAbsVy,rmsV,velocityMismatches,failed_metrics,compared_metrics,verdict,shadowCsv,compareCsv,compareSummary\n' > "$OUT_CSV"

read_elapsed() {
  python3 - "$1" <<'PY'
import csv, sys
with open(sys.argv[1], newline='') as f:
    rows=list(csv.DictReader(f))
print(rows[0].get('elapsed_s', 'nan'))
PY
}

append_shadow_summary() {
  local label=$1 nx=$2 ny=$3 steps=$4 case_name=$5 baseline_summary=$6 shadow_summary=$7 shadow_csv=$8 compare_csv=$9 compare_summary=${10} baseline_elapsed=${11} shadow_elapsed=${12}
  python3 - "$label" "$nx" "$ny" "$steps" "$case_name" "$baseline_summary" "$shadow_summary" "$shadow_csv" "$compare_csv" "$compare_summary" "$baseline_elapsed" "$shadow_elapsed" "$OUT_CSV" <<'PY'
import csv, sys
(label, nx, ny, steps, case_name, baseline_summary, shadow_summary, shadow_csv, compare_csv, compare_summary, baseline_elapsed_s, shadow_elapsed_s, out_csv) = sys.argv[1:14]

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
shadow = read_one(shadow_summary)
compare = read_one(compare_summary)
with open(shadow_csv, newline='') as fp:
    rows=list(csv.DictReader(fp))
if not rows:
    raise SystemExit(f"empty CUDA SRC collision shadow CSV: {shadow_csv}")

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
shadow_elapsed=float(shadow_elapsed_s)
base_wall=f(base,'wallTime')
shadow_wall=f(shadow,'wallTime')
failed=i(compare,'failed_metrics','999999')
compared=i(compare,'compared_metrics','0')
velocity_mismatches=sum(i(r,'velocityMismatches','0') for r in rows)
invalid=sum(i(r,'invalidCellParticles','0') for r in rows)
max_vx=max(vals('maxAbsVx'))
max_vy=max(vals('maxAbsVy'))
verdict='PASS' if failed==0 and velocity_mismatches==0 and invalid==0 else 'FAIL'
row={
    'grid': label,
    'NX': nx,
    'NY': ny,
    'steps': steps,
    'case': case_name,
    'baselineElapsed_s': base_elapsed,
    'shadowElapsed_s': shadow_elapsed,
    'baselineWallTime': base_wall,
    'shadowWallTime': shadow_wall,
    'elapsedDelta_s': shadow_elapsed-base_elapsed,
    'wallDelta_s': shadow_wall-base_wall,
    'shadowCalls': calls,
    'particlesVisitedPerCall': last('particlesVisited'),
    'particlesRotatedPerCall': last('particlesRotated'),
    'invalidCellParticles': invalid,
    'numCells': last('numCells'),
    'totalShadowSeconds': sum(vals('totalSeconds')),
    'uploadSeconds': sum(vals('uploadSeconds')),
    'kernelSeconds': sum(vals('kernelSeconds')),
    'downloadSeconds': sum(vals('downloadSeconds')),
    'avgShadowTotalSeconds': sum(vals('totalSeconds'))/calls,
    'avgKernelSeconds': sum(vals('kernelSeconds'))/calls,
    'maxAbsVx': max_vx,
    'maxAbsVy': max_vy,
    'rmsV': max(vals('rmsV')),
    'velocityMismatches': velocity_mismatches,
    'failed_metrics': failed,
    'compared_metrics': compared,
    'verdict': verdict,
    'shadowCsv': shadow_csv,
    'compareCsv': compare_csv,
    'compareSummary': compare_summary,
}
fieldnames=['grid','NX','NY','steps','case','baselineElapsed_s','shadowElapsed_s','baselineWallTime','shadowWallTime','elapsedDelta_s','wallDelta_s','shadowCalls','particlesVisitedPerCall','particlesRotatedPerCall','invalidCellParticles','numCells','totalShadowSeconds','uploadSeconds','kernelSeconds','downloadSeconds','avgShadowTotalSeconds','avgKernelSeconds','maxAbsVx','maxAbsVy','rmsV','velocityMismatches','failed_metrics','compared_metrics','verdict','shadowCsv','compareCsv','compareSummary']
with open(out_csv, 'a', newline='') as fcsv:
    writer=csv.DictWriter(fcsv, fieldnames=fieldnames)
    writer.writerow(row)
print(f"[0210-src-shadow] {verdict} {label}/{case_name}: shadowWall={shadow_wall:.6g}s baselineWall={base_wall:.6g}s totalShadow={row['totalShadowSeconds']:.6g}s kernel={row['kernelSeconds']:.6g}s maxV=({max_vx:.3g},{max_vy:.3g}) failed={failed}/{compared}")
if verdict != 'PASS':
    raise SystemExit(1)
PY
}

run_one() {
  local nx=$1 steps=$2 ny=${NY_OVERRIDE:-$nx}
  local label="${nx}x${ny}_s${steps}"
  local seed=$((SEED_BASE + nx + steps))
  local summary_every=${SUMMARY_EVERY_OVERRIDE:-$SUMMARY_EVERY_DEFAULT}
  local base_root="runs/cuda_src_collision_shadow_0210_baseline_${label}"
  local shadow_root="runs/cuda_src_collision_shadow_0210_${label}"

  if [[ "$RUN_BASELINE" != "1" ]]; then
    echo "[0210-src-shadow] ERROR: RUN_BASELINE=0 is not supported for this harness" >&2
    exit 4
  fi

  echo "[0210-src-shadow] baseline $label"
  env BIN="$BIN" BUILD_IF_MISSING=0 CASE_LIST="$CASE_LIST" \
      NX="$nx" NY="$ny" GAMMA="$GAMMA" STEPS="$steps" SUMMARY_EVERY="$summary_every" \
      THREADS="$THREADS" SEED="$seed" DUMP_STATE_EVERY=0 \
      RUN_ROOT="$base_root" RUN_TAG="cuda0210_baseline_${label}" PROJECTION_BACKEND="$PROJECTION_BACKEND" \
      MPCD_CUDA_CELL_MOMENTS_USE=${MPCD_CUDA_CELL_MOMENTS_USE:-0} \
      MPCD_CUDA_CELL_MOMENTS_SHADOW=0 \
      MPCD_CUDA_THERMOSTAT_USE=${MPCD_CUDA_THERMOSTAT_USE:-0} \
      MPCD_CUDA_THERMOSTAT_SHADOW=0 \
      MPCD_CUDA_SRC_COLLISION_SHADOW=0 \
      bash scripts/run_validation_mono_config_0162.sh
  local base_summary="$base_root/validation_summary_0162.csv"
  local base_elapsed
  base_elapsed=$(read_elapsed "$base_summary")

  echo "[0210-src-shadow] shadow $label"
  env BIN="$BIN" BUILD_IF_MISSING=0 CASE_LIST="$CASE_LIST" \
      NX="$nx" NY="$ny" GAMMA="$GAMMA" STEPS="$steps" SUMMARY_EVERY="$summary_every" \
      THREADS="$THREADS" SEED="$seed" DUMP_STATE_EVERY=0 \
      RUN_ROOT="$shadow_root" RUN_TAG="cuda0210_shadow_${label}" PROJECTION_BACKEND="$PROJECTION_BACKEND" \
      MPCD_CUDA_CELL_MOMENTS_USE=${MPCD_CUDA_CELL_MOMENTS_USE:-0} \
      MPCD_CUDA_CELL_MOMENTS_SHADOW=0 \
      MPCD_CUDA_THERMOSTAT_USE=${MPCD_CUDA_THERMOSTAT_USE:-0} \
      MPCD_CUDA_THERMOSTAT_SHADOW=0 \
      MPCD_CUDA_SRC_COLLISION_SHADOW=1 \
      MPCD_CUDA_SRC_COLLISION_SHADOW_TOL="$SHADOW_TOL" \
      MPCD_CUDA_SRC_COLLISION_THREADS_PER_BLOCK=${MPCD_CUDA_SRC_COLLISION_THREADS_PER_BLOCK:-256} \
      bash scripts/run_validation_mono_config_0162.sh
  local shadow_summary="$shadow_root/validation_summary_0162.csv"
  local shadow_elapsed
  shadow_elapsed=$(read_elapsed "$shadow_summary")

  local compare_csv="$ART_DIR/cuda_src_collision_shadow_compare_0210_${label}.csv"
  local compare_summary="$ART_DIR/cuda_src_collision_shadow_compare_summary_0210_${label}.csv"
  python3 scripts/compare_validation_mono_config_0162.py \
    --origin "$base_root" \
    --optimized "$shadow_root" \
    --out "$compare_csv" \
    --summary-out "$compare_summary"

  local case_name
  for case_name in $CASE_LIST; do
    local shadow_csv="$shadow_root/$case_name/cuda_src_collision_shadow_0210.csv"
    if [[ ! -f "$shadow_csv" ]]; then
      echo "[0210-src-shadow] ERROR: missing $shadow_csv" >&2
      exit 3
    fi
    append_shadow_summary "$label" "$nx" "$ny" "$steps" "$case_name" \
      "$base_summary" "$shadow_summary" "$shadow_csv" "$compare_csv" "$compare_summary" \
      "$base_elapsed" "$shadow_elapsed"
  done
}

for spec in $GRID_CASES; do
  IFS=: read -r nx steps <<< "$spec"
  if [[ -z "${nx:-}" || -z "${steps:-}" ]]; then
    echo "[0210-src-shadow] invalid GRID_CASES entry '$spec' (expected NX:steps)" >&2
    exit 2
  fi
  run_one "$nx" "$steps"
done

echo "[0210-src-shadow] wrote $OUT_CSV"
