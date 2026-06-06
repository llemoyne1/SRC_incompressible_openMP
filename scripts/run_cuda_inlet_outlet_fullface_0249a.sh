#!/usr/bin/env bash
set -euo pipefail

# 0249a — unsegmented full-face inlet/outlet CUDA validation.
# Scope: open_rect_obstacle_full only. The CUDA kernel marks full-face
# inlet-backflow/outlet-crossing particles inactive before the existing CPU hard
# reservoir rebuild inserts the deterministic inlet band. Segmented apertures,
# recycle mode and Q6 remain CPU.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BIN=${BIN:-build/src_mpcd_base_cuda_0249a}
ART_DIR=${ART_DIR:-dev_history/artifacts/gpu_cuda_inlet_outlet_0249a}
GRID_CASES=${GRID_CASES:-"64:300 128:300"}
CASE_LIST=${CASE_LIST:-"open_rect_obstacle_full"}
GAMMA=${GAMMA:-20}
THREADS=${THREADS:-8}
SUMMARY_EVERY_DEFAULT=${SUMMARY_EVERY:-50}
SEED_BASE=${SEED_BASE:-162049}
PROJECTION_BACKEND=${PROJECTION_BACKEND:-cpu}
PROJECTION_ENABLE=${PROJECTION_ENABLE:-true}
STOP_ON_FAIL=${STOP_ON_FAIL:-1}

BASELINE_MODE_NAME=${BASELINE_MODE_NAME:-cpu_baseline}
STACK_MODE_NAME=${STACK_MODE_NAME:-cuda_boundary_stack_0248}
IO_MODE_NAME=${IO_MODE_NAME:-cuda_inlet_outlet_fullface_0249a}

mkdir -p "$ART_DIR"

if [[ ! -x "$BIN" ]]; then
  OUT="$BIN" CUDA_ARCH_FLAGS=${CUDA_ARCH_FLAGS:-} bash scripts/build_src_mpcd_cuda_0249a.sh
fi
if [[ ! -x "$BIN" ]]; then
  echo "[0249a-inlet-outlet] ERROR: missing binary $BIN" >&2
  exit 127
fi

OUT_CSV=${OUT_CSV:-$ART_DIR/cuda_inlet_outlet_fullface_0249a.csv}
printf 'caseList,grid,NX,NY,steps,mode,resamplingCuda,periodicStreamingCuda,wallSimpleStreamingCuda,immersedRectangleCuda,pistonStreamingCuda,inletOutletFullfaceCuda,projectionEnable,projectionBackend,runExitCode,baselineWallTime,modeWallTime,wallDelta_s,wallSpeedup,failed_metrics,compared_metrics,verdict,stdoutLog,stderrLog,compareCsv,compareSummary\n' > "$OUT_CSV"

summary_wall() {
  local summary=$1
  python3 - "$summary" <<'PY'
import csv, sys
p=sys.argv[1]
try:
    with open(p, newline='') as f:
        rows=list(csv.DictReader(f))
    vals=[]
    for r in rows:
        for k in ('wallTime','wallTime_s','elapsed_s','elapsedSeconds'):
            if k in r and r[k] not in ('', 'nan'):
                vals.append(float(r[k])); break
    print(max(vals) if vals else 'nan')
except Exception:
    print('nan')
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
  local periodic_cuda=0
  local wall_cuda=0
  local immersed_cuda=0
  local piston_cuda=0
  local io_cuda=0

  case "$mode" in
    "$BASELINE_MODE_NAME")
      ;;
    "$STACK_MODE_NAME")
      resampling_cuda=1; resampling_download_all=0; resampling_host_shadow=1; resampling_upload_mode=roles_only
      periodic_cuda=1; wall_cuda=1; immersed_cuda=1; piston_cuda=1 ;;
    "$IO_MODE_NAME")
      resampling_cuda=1; resampling_download_all=0; resampling_host_shadow=1; resampling_upload_mode=roles_only
      periodic_cuda=1; wall_cuda=1; immersed_cuda=1; piston_cuda=1; io_cuda=1 ;;
    *) echo "[0249a-inlet-outlet] ERROR: unknown mode $mode" >&2; return 2 ;;
  esac

  set +e
  env BIN="$BIN" BUILD_IF_MISSING=0 CASE_LIST="$CASE_LIST" \
      NX="$nx" NY="$ny" GAMMA="$GAMMA" STEPS="$steps" SUMMARY_EVERY="$summary_every" \
      THREADS="$THREADS" SEED="$seed" DUMP_STATE_EVERY=0 \
      RUN_ROOT="$root" RUN_TAG="$tag" PROJECTION_BACKEND="$PROJECTION_BACKEND" PROJECTION_ENABLE="$PROJECTION_ENABLE" \
      MPCD_CUDA_CELL_MOMENTS_USE=0 \
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
      MPCD_CUDA_STREAMING_PERIODIC_0245="$periodic_cuda" \
      MPCD_CUDA_STREAMING_PERIODIC_0245_THREADS="${MPCD_CUDA_STREAMING_PERIODIC_0245_THREADS:-256}" \
      MPCD_CUDA_STREAMING_WALL_SIMPLE_0246="$wall_cuda" \
      MPCD_CUDA_STREAMING_WALL_SIMPLE_0246_THREADS="${MPCD_CUDA_STREAMING_WALL_SIMPLE_0246_THREADS:-256}" \
      MPCD_CUDA_IMMERSED_RECTANGLE_0247="$immersed_cuda" \
      MPCD_CUDA_IMMERSED_RECTANGLE_0247_THREADS="${MPCD_CUDA_IMMERSED_RECTANGLE_0247_THREADS:-256}" \
      MPCD_CUDA_STREAMING_PISTON_0247B="$piston_cuda" \
      MPCD_CUDA_STREAMING_PISTON_0247B_THREADS="${MPCD_CUDA_STREAMING_PISTON_0247B_THREADS:-256}" \
      MPCD_CUDA_INLET_OUTLET_FULLFACE_0249A="$io_cuda" \
      MPCD_CUDA_INLET_OUTLET_FULLFACE_0249A_THREADS="${MPCD_CUDA_INLET_OUTLET_FULLFACE_0249A_THREADS:-256}" \
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

case_list_csv=$(csv_quote "$CASE_LIST")
for spec in $GRID_CASES; do
  IFS=: read -r nx steps <<<"$spec"
  ny=${NY_OVERRIDE:-$nx}
  grid="${nx}x${ny}_s${steps}"

  base_root="runs/cuda_inlet_outlet_0249a_${BASELINE_MODE_NAME}_${grid}"
  base_stdout="$ART_DIR/cuda_inlet_outlet_0249a_${BASELINE_MODE_NAME}_${grid}.stdout.log"
  base_stderr="$ART_DIR/cuda_inlet_outlet_0249a_${BASELINE_MODE_NAME}_${grid}.stderr.log"
  echo "[0249a-inlet-outlet] running baseline grid=$grid cases=[$CASE_LIST]"
  run_validation_logged "$nx" "$ny" "$steps" "$base_root" "cuda0249a_${BASELINE_MODE_NAME}_${grid}" "$BASELINE_MODE_NAME" "$base_stdout" "$base_stderr"
  base_rc=$?
  base_wall=$(summary_wall "$base_root/validation_summary_0162.csv")
  printf '%s,%s,%s,%s,%s,%s,0,0,0,0,0,0,%s,%s,%s,%s,%s,0,1,0,0,%s,%s,%s,none,none\n' \
    "$case_list_csv" "$grid" "$nx" "$ny" "$steps" "$BASELINE_MODE_NAME" "$PROJECTION_ENABLE" "$PROJECTION_BACKEND" "$base_rc" "$base_wall" "$base_wall" \
    "$([[ $base_rc -eq 0 ]] && echo PASS || echo FAIL)" "$base_stdout" "$base_stderr" >> "$OUT_CSV"

  for mode in "$STACK_MODE_NAME" "$IO_MODE_NAME"; do
    run_root="runs/cuda_inlet_outlet_0249a_${mode}_${grid}"
    stdout_log="$ART_DIR/cuda_inlet_outlet_0249a_${mode}_${grid}.stdout.log"
    stderr_log="$ART_DIR/cuda_inlet_outlet_0249a_${mode}_${grid}.stderr.log"
    compare_csv="$ART_DIR/cuda_inlet_outlet_compare_0249a_${mode}_${grid}.csv"
    compare_summary="$ART_DIR/cuda_inlet_outlet_compare_summary_0249a_${mode}_${grid}.csv"
    echo "[0249a-inlet-outlet] running mode=$mode grid=$grid"
    run_validation_logged "$nx" "$ny" "$steps" "$run_root" "cuda0249a_${mode}_${grid}" "$mode" "$stdout_log" "$stderr_log"
    rc=$?
    wall=$(summary_wall "$run_root/validation_summary_0162.csv")
    compare_runs "$base_root" "$run_root" "$compare_csv" "$compare_summary" "$stdout_log" "$stderr_log" || true
    IFS=, read -r failed compared verdict < <(read_compare_summary "$compare_summary")

    resampling_flag=1; periodic_flag=1; wall_flag=1; immersed_flag=1; piston_flag=1; io_flag=0
    if [[ "$mode" == "$IO_MODE_NAME" ]]; then
      io_flag=1
    fi
    python3 - <<PY >> "$OUT_CSV"
import math
base=float('$base_wall') if '$base_wall' != 'nan' else float('nan')
wall=float('$wall') if '$wall' != 'nan' else float('nan')
speed=base/wall if math.isfinite(base) and math.isfinite(wall) and wall>0 else float('nan')
delta=wall-base if math.isfinite(base) and math.isfinite(wall) else float('nan')
print(f"$case_list_csv,$grid,$nx,$ny,$steps,$mode,$resampling_flag,$periodic_flag,$wall_flag,$immersed_flag,$piston_flag,$io_flag,$PROJECTION_ENABLE,$PROJECTION_BACKEND,$rc,{base},{wall},{delta},{speed},$failed,$compared,$verdict,$stdout_log,$stderr_log,$compare_csv,$compare_summary")
PY
    echo "[0249a-inlet-outlet] $verdict mode=$mode grid=$grid: wall=$wall baseline=$base_wall failed=$failed/$compared"
    if [[ "$STOP_ON_FAIL" == "1" && ( "$rc" != "0" || "$failed" != "0" || "$verdict" != "PASS" ) ]]; then
      exit 1
    fi
  done

done

echo "[0249a-inlet-outlet] wrote $OUT_CSV"
echo "[0249a-inlet-outlet] Segmented openBoundarySegment* remains CPU; Q6/Q9, collision and hard-reservoir insertion stay CPU."
