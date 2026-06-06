#!/usr/bin/env bash
set -euo pipefail

# 0250 — first gain-oriented integration step.
# Compare the already validated CUDA boundary/resampling stack against the same
# stack plus active CUDA particle->cell moments inside src_collision_step.
# Collision rotation, thermostat, virial and Q6/Q9 remain CPU.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BIN=${BIN:-build/src_mpcd_base_cuda_0250}
ART_DIR=${ART_DIR:-dev_history/artifacts/gpu_cuda_cell_moments_0250}
GRID_CASES=${GRID_CASES:-"64:300 128:300"}
CASE_LIST=${CASE_LIST:-"tg_periodic_full poiseuille_wall_full open_rect_obstacle_full piston_virial_full segmented_u_turn_full"}
GAMMA=${GAMMA:-20}
THREADS=${THREADS:-8}
SUMMARY_EVERY_DEFAULT=${SUMMARY_EVERY:-50}
SEED_BASE=${SEED_BASE:-162050}
PROJECTION_BACKEND=${PROJECTION_BACKEND:-cpu}
PROJECTION_ENABLE=${PROJECTION_ENABLE:-true}
STOP_ON_FAIL=${STOP_ON_FAIL:-1}

BASELINE_MODE_NAME=${BASELINE_MODE_NAME:-cpu_baseline}
STACK_MODE_NAME=${STACK_MODE_NAME:-cuda_boundary_stack_0249b}
CELL_MODE_NAME=${CELL_MODE_NAME:-cuda_boundary_stack_cell_moments_0250}

mkdir -p "$ART_DIR"

if [[ ! -x "$BIN" ]]; then
  OUT="$BIN" CUDA_ARCH_FLAGS=${CUDA_ARCH_FLAGS:-} bash scripts/build_src_mpcd_cuda_0250.sh
fi
if [[ ! -x "$BIN" ]]; then
  echo "[0250-cell-moments] ERROR: missing binary $BIN" >&2
  exit 127
fi

OUT_CSV=${OUT_CSV:-$ART_DIR/cuda_boundary_cell_moments_0250.csv}
printf 'caseList,grid,NX,NY,steps,mode,resamplingCuda,boundaryStackCuda,cellMomentsCuda,projectionEnable,projectionBackend,runExitCode,baselineTotalWallTime,modeTotalWallTime,totalWallDelta_s,totalWallSpeedup,baselineMaxCaseWallTime,modeMaxCaseWallTime,maxCaseWallDelta_s,maxCaseWallSpeedup,cellActiveCalls,cellParticlesVisitedPerCall,cellFluidParticlesPerCall,cellNumCells,cellTotalSeconds,cellUploadSeconds,cellKernelSeconds,cellDownloadSeconds,cellAvgTotalSeconds,cellAvgKernelSeconds,cellReuseBufferFraction,cellAllFluidFastPathFraction,cellUniformMassFastPathFraction,cellDownloadedVelocitiesFraction,failed_metrics,compared_metrics,verdict,stdoutLog,stderrLog,compareCsv,compareSummary\n' > "$OUT_CSV"

summary_times() {
  local summary=$1
  python3 - "$summary" <<'PY'
import csv, math, sys
p=sys.argv[1]
try:
    with open(p, newline='') as f:
        rows=list(csv.DictReader(f))
    vals=[]
    for r in rows:
        v=None
        for k in ('elapsed_s','wallTime','wallTime_s','elapsedSeconds'):
            if k in r and r[k] not in ('', 'nan'):
                v=float(r[k]); break
        if v is not None:
            vals.append(v)
    total=sum(vals) if vals else float('nan')
    mx=max(vals) if vals else float('nan')
    print(f'{total},{mx}')
except Exception:
    print('nan,nan')
PY
}

read_compare_summary() {
  local f=$1
  python3 - "$f" <<'PY'
import csv, sys
p=sys.argv[1]
failed=999999; compared=0; verdict='FAIL'
try:
    with open(p, newline='') as fh:
        rows=list(csv.DictReader(fh))
    if rows:
        r=rows[-1]
        for k in ('failed_metrics','failed','nFailed'):
            if k in r and r[k] != '':
                failed=int(float(r[k])); break
        for k in ('compared_metrics','compared','nCompared'):
            if k in r and r[k] != '':
                compared=int(float(r[k])); break
        verdict=r.get('verdict', 'PASS' if failed==0 else 'FAIL')
except Exception:
    pass
print(f'{failed},{compared},{verdict}')
PY
}

cell_moments_stats() {
  local root=$1
  python3 - "$root" <<'PY'
import csv, glob, math, os, sys
root=sys.argv[1]
paths=glob.glob(os.path.join(root, '*', 'cuda_cell_moments_active_0202.csv'))
rows=[]
for p in paths:
    try:
        with open(p, newline='') as f:
            rows.extend(list(csv.DictReader(f)))
    except FileNotFoundError:
        pass
if not rows:
    print('0,nan,nan,nan,0,0,0,0,nan,nan,nan,nan,nan,nan')
    raise SystemExit(0)
def sf(k):
    out=[]
    for r in rows:
        try:
            out.append(float(r.get(k, 'nan')))
        except Exception:
            out.append(float('nan'))
    return out
calls=len(rows)
particles=sf('particlesVisited')[0]
fluid=sf('fluidParticles')[0]
num_cells=sf('numCells')[0]
total=sum(x for x in sf('totalSeconds') if math.isfinite(x))
upload=sum(x for x in sf('uploadSeconds') if math.isfinite(x))
kernel=sum(x for x in sf('kernelSeconds') if math.isfinite(x))
download=sum(x for x in sf('downloadSeconds') if math.isfinite(x))
reuse=sum(x for x in sf('reusedDeviceBuffers') if math.isfinite(x))/calls
allfluid=sum(x for x in sf('allFluidFastPath') if math.isfinite(x))/calls
uniform=sum(x for x in sf('uniformMassFastPath') if math.isfinite(x))/calls
downvel=sum(x for x in sf('downloadedCellVelocities') if math.isfinite(x))/calls
print(f'{calls},{particles},{fluid},{num_cells},{total},{upload},{kernel},{download},{total/calls},{kernel/calls},{reuse},{allfluid},{uniform},{downvel}')
PY
}

csv_quote() {
  python3 - "$1" <<'PY'
import csv, io, sys
out=io.StringIO(); csv.writer(out).writerow([sys.argv[1]])
print(out.getvalue().strip())
PY
}

run_validation_logged() {
  local nx=$1 ny=$2 steps=$3 root=$4 tag=$5 mode=$6 stdout_log=$7 stderr_log=$8
  local summary_every=${SUMMARY_EVERY_OVERRIDE:-$SUMMARY_EVERY_DEFAULT}
  local seed=$((SEED_BASE + nx + steps))

  local resampling_cuda=0
  local resampling_download_all=1
  local resampling_host_shadow=0
  local resampling_upload_mode=all
  local boundary_cuda=0
  local cell_cuda=0

  case "$mode" in
    "$BASELINE_MODE_NAME")
      ;;
    "$STACK_MODE_NAME")
      resampling_cuda=1; resampling_download_all=0; resampling_host_shadow=1; resampling_upload_mode=roles_only
      boundary_cuda=1 ;;
    "$CELL_MODE_NAME")
      resampling_cuda=1; resampling_download_all=0; resampling_host_shadow=1; resampling_upload_mode=roles_only
      boundary_cuda=1; cell_cuda=1 ;;
    *) echo "[0250-cell-moments] ERROR: unknown mode $mode" >&2; return 2 ;;
  esac

  set +e
  env BIN="$BIN" BUILD_IF_MISSING=0 CASE_LIST="$CASE_LIST" \
      NX="$nx" NY="$ny" GAMMA="$GAMMA" STEPS="$steps" SUMMARY_EVERY="$summary_every" \
      THREADS="$THREADS" SEED="$seed" DUMP_STATE_EVERY=0 \
      RUN_ROOT="$root" RUN_TAG="$tag" PROJECTION_BACKEND="$PROJECTION_BACKEND" PROJECTION_ENABLE="$PROJECTION_ENABLE" \
      MPCD_CUDA_CELL_MOMENTS_USE="$cell_cuda" \
      MPCD_CUDA_CELL_MOMENTS_REUSE_BUFFERS=${MPCD_CUDA_CELL_MOMENTS_REUSE_BUFFERS:-1} \
      MPCD_CUDA_CELL_MOMENTS_ALL_FLUID_FASTPATH=${MPCD_CUDA_CELL_MOMENTS_ALL_FLUID_FASTPATH:-1} \
      MPCD_CUDA_CELL_MOMENTS_UNIFORM_MASS_FASTPATH=${MPCD_CUDA_CELL_MOMENTS_UNIFORM_MASS_FASTPATH:-1} \
      MPCD_CUDA_CELL_MOMENTS_THREADS_PER_BLOCK=${MPCD_CUDA_CELL_MOMENTS_THREADS_PER_BLOCK:-256} \
      MPCD_CUDA_CELL_MOMENTS_SHADOW=0 \
      MPCD_CUDA_THERMOSTAT_USE=0 \
      MPCD_CUDA_SRC_COLLISION_USE=0 \
      MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=0 \
      MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE=0 \
      MPCD_CUDA_PERSISTENT_PARTICLE_STATE_USE=0 \
      MPCD_CUDA_PERSISTENT_PARTICLE_METADATA_CACHE=0 \
      MPCD_CUDA_PERSISTENT_CELL_WORKSPACE_USE=0 \
      MPCD_CUDA_RESAMPLING_EXTRACTION_USE=0 \
      MPCD_CUDA_RESAMPLING_INSERTION_USE=0 \
      MPCD_CUDA_RESAMPLING_PERSISTENT_0240="$resampling_cuda" \
      MPCD_CUDA_RESAMPLING_PERSISTENT_0240_MIN_PARTICLES=0 \
      MPCD_CUDA_RESAMPLING_PERSISTENT_ACTIVE_PATH_0241_STRICT=1 \
      MPCD_CUDA_RESAMPLING_PERSISTENT_ACTIVE_PATH_0242_UPLOAD_MODE="$resampling_upload_mode" \
      MPCD_CUDA_RESAMPLING_PERSISTENT_ACTIVE_PATH_0242_DOWNLOAD_ALL="$resampling_download_all" \
      MPCD_CUDA_RESAMPLING_PERSISTENT_ACTIVE_PATH_0242_HOST_SHADOW_AUTHORITATIVE="$resampling_host_shadow" \
      MPCD_CUDA_STREAMING_PERIODIC_0245="$boundary_cuda" \
      MPCD_CUDA_STREAMING_PERIODIC_0245_THREADS="${MPCD_CUDA_STREAMING_PERIODIC_0245_THREADS:-256}" \
      MPCD_CUDA_STREAMING_WALL_SIMPLE_0246="$boundary_cuda" \
      MPCD_CUDA_STREAMING_WALL_SIMPLE_0246_THREADS="${MPCD_CUDA_STREAMING_WALL_SIMPLE_0246_THREADS:-256}" \
      MPCD_CUDA_IMMERSED_RECTANGLE_0247="$boundary_cuda" \
      MPCD_CUDA_IMMERSED_RECTANGLE_0247_THREADS="${MPCD_CUDA_IMMERSED_RECTANGLE_0247_THREADS:-256}" \
      MPCD_CUDA_STREAMING_PISTON_0247B="$boundary_cuda" \
      MPCD_CUDA_STREAMING_PISTON_0247B_THREADS="${MPCD_CUDA_STREAMING_PISTON_0247B_THREADS:-256}" \
      MPCD_CUDA_INLET_OUTLET_FULLFACE_0249A="$boundary_cuda" \
      MPCD_CUDA_INLET_OUTLET_SEGMENTED_0249B="$boundary_cuda" \
      MPCD_CUDA_INLET_OUTLET_FULLFACE_0249A_THREADS="${MPCD_CUDA_INLET_OUTLET_FULLFACE_0249A_THREADS:-256}" \
      MPCD_CUDA_INLET_OUTLET_SEGMENTED_0249B_THREADS="${MPCD_CUDA_INLET_OUTLET_SEGMENTED_0249B_THREADS:-256}" \
      bash scripts/run_validation_mono_config_0162.sh >"$stdout_log" 2>"$stderr_log"
  local rc=$?
  set -e
  return $rc
}

compare_runs() {
  local base_root=$1 run_root=$2 compare_csv=$3 compare_summary=$4 stdout_log=$5 stderr_log=$6
  if [[ -f "$base_root/validation_summary_0162.csv" && -f "$run_root/validation_summary_0162.csv" ]]; then
    set +e
    python3 scripts/compare_validation_mono_config_0162.py \
      --origin "$base_root" --optimized "$run_root" \
      --out "$compare_csv" --summary-out "$compare_summary" >>"$stdout_log" 2>>"$stderr_log"
    local rc=$?
    set -e
    return $rc
  fi
  return 99
}

append_row() {
  local mode=$1 grid=$2 nx=$3 ny=$4 steps=$5 rc=$6 base_total=$7 mode_total=$8 base_max=$9 mode_max=${10} failed=${11} compared=${12} verdict=${13} stdout_log=${14} stderr_log=${15} compare_csv=${16} compare_summary=${17} root=${18}
  local resampling_flag=0 boundary_flag=0 cell_flag=0
  if [[ "$mode" == "$STACK_MODE_NAME" || "$mode" == "$CELL_MODE_NAME" ]]; then
    resampling_flag=1; boundary_flag=1
  fi
  if [[ "$mode" == "$CELL_MODE_NAME" ]]; then
    cell_flag=1
  fi
  IFS=, read -r cell_calls cell_particles cell_fluid cell_cells cell_total cell_upload cell_kernel cell_download cell_avg_total cell_avg_kernel cell_reuse cell_allfluid cell_uniform cell_downvel < <(cell_moments_stats "$root")
  python3 - <<PY >> "$OUT_CSV"
import math
case_list = '''$case_list_csv'''
base_total=float('$base_total') if '$base_total' != 'nan' else float('nan')
mode_total=float('$mode_total') if '$mode_total' != 'nan' else float('nan')
base_max=float('$base_max') if '$base_max' != 'nan' else float('nan')
mode_max=float('$mode_max') if '$mode_max' != 'nan' else float('nan')
total_speed=base_total/mode_total if math.isfinite(base_total) and math.isfinite(mode_total) and mode_total>0 else float('nan')
max_speed=base_max/mode_max if math.isfinite(base_max) and math.isfinite(mode_max) and mode_max>0 else float('nan')
total_delta=mode_total-base_total if math.isfinite(base_total) and math.isfinite(mode_total) else float('nan')
max_delta=mode_max-base_max if math.isfinite(base_max) and math.isfinite(mode_max) else float('nan')
print(f"{case_list},$grid,$nx,$ny,$steps,$mode,$resampling_flag,$boundary_flag,$cell_flag,$PROJECTION_ENABLE,$PROJECTION_BACKEND,$rc,{base_total},{mode_total},{total_delta},{total_speed},{base_max},{mode_max},{max_delta},{max_speed},$cell_calls,$cell_particles,$cell_fluid,$cell_cells,$cell_total,$cell_upload,$cell_kernel,$cell_download,$cell_avg_total,$cell_avg_kernel,$cell_reuse,$cell_allfluid,$cell_uniform,$cell_downvel,$failed,$compared,$verdict,$stdout_log,$stderr_log,$compare_csv,$compare_summary")
PY
}

case_list_csv=$(csv_quote "$CASE_LIST")
for spec in $GRID_CASES; do
  IFS=: read -r nx steps <<<"$spec"
  ny=${NY_OVERRIDE:-$nx}
  grid="${nx}x${ny}_s${steps}"

  base_root="runs/cuda_cell_moments_0250_${BASELINE_MODE_NAME}_${grid}"
  base_stdout="$ART_DIR/cuda_cell_moments_0250_${BASELINE_MODE_NAME}_${grid}.stdout.log"
  base_stderr="$ART_DIR/cuda_cell_moments_0250_${BASELINE_MODE_NAME}_${grid}.stderr.log"
  echo "[0250-cell-moments] running baseline grid=$grid cases=[$CASE_LIST]"
  run_validation_logged "$nx" "$ny" "$steps" "$base_root" "cuda0250_${BASELINE_MODE_NAME}_${grid}" "$BASELINE_MODE_NAME" "$base_stdout" "$base_stderr"
  base_rc=$?
  IFS=, read -r base_total base_max < <(summary_times "$base_root/validation_summary_0162.csv")
  append_row "$BASELINE_MODE_NAME" "$grid" "$nx" "$ny" "$steps" "$base_rc" "$base_total" "$base_total" "$base_max" "$base_max" 0 0 "$([[ $base_rc -eq 0 ]] && echo PASS || echo FAIL)" "$base_stdout" "$base_stderr" none none "$base_root"

  for mode in "$STACK_MODE_NAME" "$CELL_MODE_NAME"; do
    run_root="runs/cuda_cell_moments_0250_${mode}_${grid}"
    stdout_log="$ART_DIR/cuda_cell_moments_0250_${mode}_${grid}.stdout.log"
    stderr_log="$ART_DIR/cuda_cell_moments_0250_${mode}_${grid}.stderr.log"
    compare_csv="$ART_DIR/cuda_cell_moments_compare_0250_${mode}_${grid}.csv"
    compare_summary="$ART_DIR/cuda_cell_moments_compare_summary_0250_${mode}_${grid}.csv"
    echo "[0250-cell-moments] running mode=$mode grid=$grid"
    run_validation_logged "$nx" "$ny" "$steps" "$run_root" "cuda0250_${mode}_${grid}" "$mode" "$stdout_log" "$stderr_log"
    rc=$?
    IFS=, read -r mode_total mode_max < <(summary_times "$run_root/validation_summary_0162.csv")
    compare_runs "$base_root" "$run_root" "$compare_csv" "$compare_summary" "$stdout_log" "$stderr_log" || true
    IFS=, read -r failed compared verdict < <(read_compare_summary "$compare_summary")
    append_row "$mode" "$grid" "$nx" "$ny" "$steps" "$rc" "$base_total" "$mode_total" "$base_max" "$mode_max" "$failed" "$compared" "$verdict" "$stdout_log" "$stderr_log" "$compare_csv" "$compare_summary" "$run_root"
    python3 - <<PY
import math
base=float('$base_total') if '$base_total' != 'nan' else float('nan')
wall=float('$mode_total') if '$mode_total' != 'nan' else float('nan')
speed=base/wall if math.isfinite(base) and math.isfinite(wall) and wall>0 else float('nan')
print(f"[0250-cell-moments] $verdict mode=$mode grid=$grid: totalWall={wall:.6g} baseline={base:.6g} speedup={speed:.6g} failed=$failed/$compared")
PY
    if [[ "$STOP_ON_FAIL" == "1" && ( "$rc" != "0" || "$failed" != "0" || "$verdict" != "PASS" ) ]]; then
      exit 1
    fi
  done

done

echo "[0250-cell-moments] wrote $OUT_CSV"
echo "[0250-cell-moments] Active CUDA cell moments enabled only in $CELL_MODE_NAME. Collision rotation, thermostat, virial and Q6/Q9 remain CPU."
