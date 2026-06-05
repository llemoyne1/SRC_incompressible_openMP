#!/usr/bin/env bash
set -euo pipefail

# 0206 — run CUDA cell-relative thermostat in shadow mode inside the real
# SRC/MPCD step. The CPU thermostat still drives the dynamics; CUDA recomputes
# the same rescale from the pre-thermostat state and compares post velocities.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BIN=${BIN:-build/src_mpcd_base_cuda_0206}
ART_DIR=${ART_DIR:-dev_history/artifacts/gpu_cuda_thermostat_0206}
GRID_CASES=${GRID_CASES:-"64:200 128:100"}
GAMMA=${GAMMA:-20}
THREADS=${THREADS:-8}
SUMMARY_EVERY_DEFAULT=${SUMMARY_EVERY:-50}
SEED_BASE=${SEED_BASE:-1620206}
PROJECTION_BACKEND=${PROJECTION_BACKEND:-cpu}
CASE_LIST=${CASE_LIST:-tg_periodic_full}
SHADOW_TOL=${SHADOW_TOL:-1e-10}
SHADOW_DIAG_TOL=${SHADOW_DIAG_TOL:-1e-10}
RUN_BASELINE=${RUN_BASELINE:-1}

mkdir -p "$ART_DIR"

if [[ ! -x "$BIN" ]]; then
  OUT="$BIN" CUDA_ARCH_FLAGS=${CUDA_ARCH_FLAGS:-} bash scripts/build_src_mpcd_cuda_0206.sh
fi
if [[ ! -x "$BIN" ]]; then
  echo "[0206-thermostat-shadow] ERROR: CUDA-enabled binary not found after build: $BIN" >&2
  exit 127
fi

OUT_CSV=${OUT_CSV:-$ART_DIR/cuda_cell_thermostat_shadow_0206.csv}
printf 'grid,NX,NY,steps,case,baselineElapsed_s,shadowElapsed_s,baselineWallTime,shadowWallTime,elapsedDelta_s,wallDelta_s,shadowCalls,particlesVisitedPerCall,fluidParticlesPerCall,numCells,totalShadowSeconds,uploadSeconds,kineticKernelSeconds,scaleKernelSeconds,applyKernelSeconds,downloadSeconds,avgShadowTotalSeconds,avgKernelSeconds,cellsRescaledCpu,cellsRescaledCuda,particlesRescaledCpu,particlesRescaledCuda,maxAbsVx,maxAbsVy,rmsV,velocityMismatches,maxDiagDiff,failed_metrics,compared_metrics,verdict,shadowCsv,compareCsv,compareSummary\n' > "$OUT_CSV"

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
import csv, math, sys
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
    raise SystemExit(f"empty CUDA thermostat shadow CSV: {shadow_csv}")

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
max_diag=max(vals('maxDiagDiff'))
max_vx=max(vals('maxAbsVx'))
max_vy=max(vals('maxAbsVy'))
verdict='PASS' if failed==0 and velocity_mismatches==0 else 'FAIL'
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
    'shadowElapsed_s': shadow_elapsed,
    'baselineWallTime': base_wall,
    'shadowWallTime': shadow_wall,
    'elapsedDelta_s': shadow_elapsed-base_elapsed,
    'wallDelta_s': shadow_wall-base_wall,
    'shadowCalls': calls,
    'particlesVisitedPerCall': last('particlesVisited'),
    'fluidParticlesPerCall': last('fluidParticles'),
    'numCells': last('numCells'),
    'totalShadowSeconds': sum(vals('totalSeconds')),
    'uploadSeconds': sum(vals('uploadSeconds')),
    'kineticKernelSeconds': kin,
    'scaleKernelSeconds': scale,
    'applyKernelSeconds': apply,
    'downloadSeconds': sum(vals('downloadSeconds')),
    'avgShadowTotalSeconds': sum(vals('totalSeconds'))/calls,
    'avgKernelSeconds': (kin+scale+apply)/calls,
    'cellsRescaledCpu': last('cellsRescaledCpu'),
    'cellsRescaledCuda': last('cellsRescaledCuda'),
    'particlesRescaledCpu': last('particlesRescaledCpu'),
    'particlesRescaledCuda': last('particlesRescaledCuda'),
    'maxAbsVx': max_vx,
    'maxAbsVy': max_vy,
    'rmsV': max(vals('rmsV')),
    'velocityMismatches': velocity_mismatches,
    'maxDiagDiff': max_diag,
    'failed_metrics': failed,
    'compared_metrics': compared,
    'verdict': verdict,
    'shadowCsv': shadow_csv,
    'compareCsv': compare_csv,
    'compareSummary': compare_summary,
}
fieldnames=['grid','NX','NY','steps','case','baselineElapsed_s','shadowElapsed_s','baselineWallTime','shadowWallTime','elapsedDelta_s','wallDelta_s','shadowCalls','particlesVisitedPerCall','fluidParticlesPerCall','numCells','totalShadowSeconds','uploadSeconds','kineticKernelSeconds','scaleKernelSeconds','applyKernelSeconds','downloadSeconds','avgShadowTotalSeconds','avgKernelSeconds','cellsRescaledCpu','cellsRescaledCuda','particlesRescaledCpu','particlesRescaledCuda','maxAbsVx','maxAbsVy','rmsV','velocityMismatches','maxDiagDiff','failed_metrics','compared_metrics','verdict','shadowCsv','compareCsv','compareSummary']
with open(out_csv, 'a', newline='') as fcsv:
    writer=csv.DictWriter(fcsv, fieldnames=fieldnames)
    writer.writerow(row)
print(f"[0206-thermostat-shadow] {verdict} {label}/{case_name}: shadowWall={shadow_wall:.6g}s baselineWall={base_wall:.6g}s totalShadow={row['totalShadowSeconds']:.6g}s kernels={row['avgKernelSeconds']*calls:.6g}s maxV=({max_vx:.3g},{max_vy:.3g}) failed={failed}/{compared}")
if verdict != 'PASS':
    raise SystemExit(1)
PY
}

run_one() {
  local nx=$1 steps=$2 ny=${NY_OVERRIDE:-$nx}
  local label="${nx}x${ny}_s${steps}"
  local seed=$((SEED_BASE + nx + steps))
  local summary_every=${SUMMARY_EVERY_OVERRIDE:-$SUMMARY_EVERY_DEFAULT}
  local base_root="runs/cuda_cell_thermostat_shadow_0206_baseline_${label}"
  local shadow_root="runs/cuda_cell_thermostat_shadow_0206_${label}"

  if [[ "$RUN_BASELINE" != "1" ]]; then
    echo "[0206-thermostat-shadow] ERROR: RUN_BASELINE=0 is not supported for this harness" >&2
    exit 4
  fi

  echo "[0206-thermostat-shadow] baseline $label"
  env BIN="$BIN" BUILD_IF_MISSING=0 CASE_LIST="$CASE_LIST" \
      NX="$nx" NY="$ny" GAMMA="$GAMMA" STEPS="$steps" SUMMARY_EVERY="$summary_every" \
      THREADS="$THREADS" SEED="$seed" DUMP_STATE_EVERY=0 \
      RUN_ROOT="$base_root" RUN_TAG="cuda0206_baseline_${label}" PROJECTION_BACKEND="$PROJECTION_BACKEND" \
      MPCD_CUDA_CELL_MOMENTS_USE=${MPCD_CUDA_CELL_MOMENTS_USE:-0} \
      MPCD_CUDA_CELL_MOMENTS_SHADOW=0 \
      MPCD_CUDA_THERMOSTAT_SHADOW=0 \
      bash scripts/run_validation_mono_config_0162.sh
  local base_summary="$base_root/validation_summary_0162.csv"
  local base_elapsed
  base_elapsed=$(read_elapsed "$base_summary")

  echo "[0206-thermostat-shadow] shadow $label"
  env BIN="$BIN" BUILD_IF_MISSING=0 CASE_LIST="$CASE_LIST" \
      NX="$nx" NY="$ny" GAMMA="$GAMMA" STEPS="$steps" SUMMARY_EVERY="$summary_every" \
      THREADS="$THREADS" SEED="$seed" DUMP_STATE_EVERY=0 \
      RUN_ROOT="$shadow_root" RUN_TAG="cuda0206_shadow_${label}" PROJECTION_BACKEND="$PROJECTION_BACKEND" \
      MPCD_CUDA_CELL_MOMENTS_USE=${MPCD_CUDA_CELL_MOMENTS_USE:-0} \
      MPCD_CUDA_CELL_MOMENTS_SHADOW=0 \
      MPCD_CUDA_THERMOSTAT_SHADOW=1 \
      MPCD_CUDA_THERMOSTAT_SHADOW_TOL="$SHADOW_TOL" \
      MPCD_CUDA_THERMOSTAT_SHADOW_DIAG_TOL="$SHADOW_DIAG_TOL" \
      MPCD_CUDA_THERMOSTAT_THREADS_PER_BLOCK=${MPCD_CUDA_THERMOSTAT_THREADS_PER_BLOCK:-256} \
      bash scripts/run_validation_mono_config_0162.sh
  local shadow_summary="$shadow_root/validation_summary_0162.csv"
  local shadow_elapsed
  shadow_elapsed=$(read_elapsed "$shadow_summary")

  local compare_csv="$ART_DIR/cuda_cell_thermostat_shadow_compare_0206_${label}.csv"
  local compare_summary="$ART_DIR/cuda_cell_thermostat_shadow_compare_summary_0206_${label}.csv"
  python3 scripts/compare_validation_mono_config_0162.py \
    --origin "$base_root" \
    --optimized "$shadow_root" \
    --out "$compare_csv" \
    --summary-out "$compare_summary"

  local case_name
  for case_name in $CASE_LIST; do
    local shadow_csv="$shadow_root/$case_name/cuda_cell_thermostat_shadow_0206.csv"
    if [[ ! -f "$shadow_csv" ]]; then
      echo "[0206-thermostat-shadow] ERROR: missing $shadow_csv" >&2
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
    echo "[0206-thermostat-shadow] invalid GRID_CASES entry '$spec' (expected NX:steps)" >&2
    exit 2
  fi
  run_one "$nx" "$steps"
done

echo "[0206-thermostat-shadow] wrote $OUT_CSV"
