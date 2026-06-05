#!/usr/bin/env bash
set -euo pipefail

# 0244 — physical active-path validation for persistent CUDA resampling.
# This is an equivalence test, not a performance migration of the full solver.
# Q6/Q9, streaming, cell moments, collision and diagnostics remain CPU here.
# Only the active persistent resampling edit is enabled in the CUDA path.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BIN=${BIN:-build/src_mpcd_base_cuda_0244}
ART_DIR=${ART_DIR:-dev_history/artifacts/gpu_cuda_resampling_0244}
GRID_CASES=${GRID_CASES:-"64:300 128:300"}
GAMMA=${GAMMA:-20}
THREADS=${THREADS:-8}
SUMMARY_EVERY_DEFAULT=${SUMMARY_EVERY:-50}
SEED_BASE=${SEED_BASE:-1620244}
PROJECTION_BACKEND=${PROJECTION_BACKEND:-cpu}
PROJECTION_ENABLE=${PROJECTION_ENABLE:-true}
STOP_ON_FAIL=${STOP_ON_FAIL:-1}
RUN_0243_SMOKE=${RUN_0243_SMOKE:-0}

# Core validation: two physically representative cases without immediately
# paying the cost/risk of obstacle and piston.  Set RUN_EXTENDED=1 to add them.
CASE_LIST_CORE=${CASE_LIST_CORE:-"tg_periodic_full poiseuille_wall_full"}
CASE_LIST_EXTENDED=${CASE_LIST_EXTENDED:-"tg_periodic_full poiseuille_wall_full open_rect_obstacle_full piston_virial_full"}
RUN_EXTENDED=${RUN_EXTENDED:-0}

# Keep the tested CUDA path identical to validated 0243 by default.
ACTIVE_UPLOAD_MODE=${ACTIVE_UPLOAD_MODE:-roles_only}
BASELINE_MODE_NAME=${BASELINE_MODE_NAME:-cpu_baseline}
ACTIVE_MODE_NAME=${ACTIVE_MODE_NAME:-persistent_active_path_0244_roles_only_physics}

mkdir -p "$ART_DIR"

if [[ ! -x "$BIN" ]]; then
  OUT="$BIN" CUDA_ARCH_FLAGS=${CUDA_ARCH_FLAGS:-} bash scripts/build_src_mpcd_cuda_0244.sh
fi
if [[ ! -x "$BIN" ]]; then
  echo "[0244-physics] ERROR: missing binary $BIN" >&2
  exit 127
fi

if [[ "$RUN_0243_SMOKE" == "1" ]]; then
  if [[ -f scripts/run_cuda_resampling_persistent_active_path_0243.sh ]]; then
    echo "[0244-physics] running 0243 smoke first"
    bash scripts/run_cuda_resampling_persistent_active_path_0243.sh
  else
    echo "[0244-physics] requested RUN_0243_SMOKE=1 but 0243 runner is absent" >&2
    exit 2
  fi
fi

OUT_CSV=${OUT_CSV:-$ART_DIR/cuda_resampling_persistent_active_physics_0244.csv}
printf 'suite,caseList,grid,NX,NY,steps,mode,projectionEnable,projectionBackend,runExitCode,baselineWallTime,modeWallTime,wallDelta_s,wallSpeedup,failed_metrics,compared_metrics,verdict,stdoutLog,stderrLog,compareCsv,compareSummary\n' > "$OUT_CSV"

summary_wall() {
  local summary=$1
  python3 - "$summary" <<'PY'
import csv, sys, math
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
out=io.StringIO()
csv.writer(out).writerow([sys.argv[1]])
print(out.getvalue().strip())
PY
}

run_validation_logged() {
  local nx=$1 ny=$2 steps=$3 case_list=$4 root=$5 tag=$6 mode=$7 stdout_log=$8 stderr_log=$9
  local summary_every=${SUMMARY_EVERY_OVERRIDE:-$SUMMARY_EVERY_DEFAULT}
  local seed=$((SEED_BASE + nx + steps))

  local persistent_active=0
  local download_all=1
  local host_shadow=0
  local upload_mode=all
  case "$mode" in
    "$BASELINE_MODE_NAME")
      persistent_active=0 ;;
    "$ACTIVE_MODE_NAME")
      persistent_active=1
      download_all=0
      host_shadow=1
      upload_mode="$ACTIVE_UPLOAD_MODE" ;;
    *) echo "[0244-physics] ERROR: unknown mode $mode" >&2; return 2 ;;
  esac

  set +e
  env BIN="$BIN" BUILD_IF_MISSING=0 CASE_LIST="$case_list" \
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
      MPCD_CUDA_RESAMPLING_PERSISTENT_0240="$persistent_active" \
      MPCD_CUDA_RESAMPLING_PERSISTENT_0240_MIN_PARTICLES=0 \
      MPCD_CUDA_RESAMPLING_PERSISTENT_ACTIVE_PATH_0241_STRICT=1 \
      MPCD_CUDA_RESAMPLING_PERSISTENT_ACTIVE_PATH_0242_UPLOAD_MODE="$upload_mode" \
      MPCD_CUDA_RESAMPLING_PERSISTENT_ACTIVE_PATH_0242_DOWNLOAD_ALL="$download_all" \
      MPCD_CUDA_RESAMPLING_PERSISTENT_ACTIVE_PATH_0242_HOST_SHADOW_AUTHORITATIVE="$host_shadow" \
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

run_suite() {
  local suite=$1 case_list=$2
  local case_list_csv
  case_list_csv=$(csv_quote "$case_list")
  for spec in $GRID_CASES; do
    IFS=: read -r nx steps <<<"$spec"
    ny=${NY_OVERRIDE:-$nx}
    grid="${nx}x${ny}_s${steps}"

    base_root="runs/cuda_resampling_persistent_active_physics_0244_${suite}_${BASELINE_MODE_NAME}_${grid}"
    base_stdout="$ART_DIR/cuda_resampling_persistent_active_physics_0244_${suite}_${BASELINE_MODE_NAME}_${grid}.stdout.log"
    base_stderr="$ART_DIR/cuda_resampling_persistent_active_physics_0244_${suite}_${BASELINE_MODE_NAME}_${grid}.stderr.log"
    echo "[0244-physics] running baseline suite=$suite grid=$grid cases=[$case_list]"
    run_validation_logged "$nx" "$ny" "$steps" "$case_list" "$base_root" "cuda0244_${suite}_${BASELINE_MODE_NAME}_${grid}" "$BASELINE_MODE_NAME" "$base_stdout" "$base_stderr"
    base_rc=$?
    base_wall=$(summary_wall "$base_root/validation_summary_0162.csv")
    printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,0,1,0,0,%s,%s,%s,none,none\n' \
      "$suite" "$case_list_csv" "$grid" "$nx" "$ny" "$steps" "$BASELINE_MODE_NAME" "$PROJECTION_ENABLE" "$PROJECTION_BACKEND" "$base_rc" "$base_wall" "$base_wall" \
      "$([[ $base_rc -eq 0 ]] && echo PASS || echo FAIL)" "$base_stdout" "$base_stderr" >> "$OUT_CSV"

    mode="$ACTIVE_MODE_NAME"
    run_root="runs/cuda_resampling_persistent_active_physics_0244_${suite}_${mode}_${grid}"
    stdout_log="$ART_DIR/cuda_resampling_persistent_active_physics_0244_${suite}_${mode}_${grid}.stdout.log"
    stderr_log="$ART_DIR/cuda_resampling_persistent_active_physics_0244_${suite}_${mode}_${grid}.stderr.log"
    compare_csv="$ART_DIR/cuda_resampling_persistent_active_physics_compare_0244_${suite}_${mode}_${grid}.csv"
    compare_summary="$ART_DIR/cuda_resampling_persistent_active_physics_compare_summary_0244_${suite}_${mode}_${grid}.csv"
    echo "[0244-physics] running active suite=$suite grid=$grid mode=$mode"
    run_validation_logged "$nx" "$ny" "$steps" "$case_list" "$run_root" "cuda0244_${suite}_${mode}_${grid}" "$mode" "$stdout_log" "$stderr_log"
    rc=$?
    wall=$(summary_wall "$run_root/validation_summary_0162.csv")
    compare_runs "$base_root" "$run_root" "$compare_csv" "$compare_summary" "$stdout_log" "$stderr_log" || true
    IFS=, read -r failed compared verdict < <(read_compare_summary "$compare_summary")
    python3 - <<PY >> "$OUT_CSV"
import math
base=float('$base_wall') if '$base_wall' != 'nan' else float('nan')
wall=float('$wall') if '$wall' != 'nan' else float('nan')
speed=base/wall if math.isfinite(base) and math.isfinite(wall) and wall>0 else float('nan')
delta=wall-base if math.isfinite(base) and math.isfinite(wall) else float('nan')
print(f"$suite,$case_list_csv,$grid,$nx,$ny,$steps,$mode,$PROJECTION_ENABLE,$PROJECTION_BACKEND,$rc,{base},{wall},{delta},{speed},$failed,$compared,$verdict,$stdout_log,$stderr_log,$compare_csv,$compare_summary")
PY
    echo "[0244-physics] $verdict suite=$suite grid=$grid: wall=$wall baseline=$base_wall failed=$failed/$compared"
    if [[ "$STOP_ON_FAIL" == "1" && ( "$rc" != "0" || "$failed" != "0" || "$verdict" != "PASS" ) ]]; then
      exit 1
    fi
  done
}

run_suite core "$CASE_LIST_CORE"
if [[ "$RUN_EXTENDED" == "1" ]]; then
  run_suite extended "$CASE_LIST_EXTENDED"
fi

echo "[0244-physics] wrote $OUT_CSV"
echo "[0244-physics] Q6/Q9 stayed CPU in this validation: PROJECTION_BACKEND=$PROJECTION_BACKEND and all non-resampling CUDA switches were forced to 0."
