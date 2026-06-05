#!/usr/bin/env bash
set -euo pipefail

# 0241 — real active-path bridge validation.
# The run compares the CPU resampling extraction/insertion path against the
# 0241 hook, which now delegates the prevalidated operation lists to the 0239
# persistent CudaParticleState kernels.  Q6 is disabled by default to isolate
# particle/resampling equivalence.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BIN=${BIN:-build/src_mpcd_base_cuda_0241}
ART_DIR=${ART_DIR:-dev_history/artifacts/gpu_cuda_resampling_0241}
GRID_CASES=${GRID_CASES:-"64:100 128:100"}
GAMMA=${GAMMA:-20}
THREADS=${THREADS:-8}
SUMMARY_EVERY_DEFAULT=${SUMMARY_EVERY:-50}
SEED_BASE=${SEED_BASE:-1620241}
CASE_LIST=${CASE_LIST:-tg_periodic_full}
PROJECTION_BACKEND=${PROJECTION_BACKEND:-cpu}
PROJECTION_ENABLE=${PROJECTION_ENABLE:-false}
STOP_ON_FAIL=${STOP_ON_FAIL:-1}
RUN_0239_SMOKE=${RUN_0239_SMOKE:-1}

mkdir -p "$ART_DIR"

if [[ ! -x "$BIN" ]]; then
  OUT="$BIN" CUDA_ARCH_FLAGS=${CUDA_ARCH_FLAGS:-} bash scripts/build_src_mpcd_cuda_0241.sh
fi
if [[ ! -x "$BIN" ]]; then
  echo "[0241-active-path] ERROR: missing binary $BIN" >&2
  exit 127
fi

if [[ "$RUN_0239_SMOKE" == "1" ]]; then
  GRID_CASES_0239=${GRID_CASES_0239:-"64:64:20 128:128:20"} \
    bash scripts/run_cuda_resampling_persistent_state_ops_smoke_0239.sh
fi

OUT_CSV=${OUT_CSV:-$ART_DIR/cuda_resampling_persistent_active_path_0241.csv}
printf 'grid,NX,NY,steps,mode,runExitCode,baselineWallTime,modeWallTime,wallDelta_s,wallSpeedup,failed_metrics,compared_metrics,verdict,stdoutLog,stderrLog,compareCsv,compareSummary\n' > "$OUT_CSV"

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

run_validation_logged() {
  local nx=$1 ny=$2 steps=$3 root=$4 tag=$5 mode=$6 stdout_log=$7 stderr_log=$8
  local summary_every=${SUMMARY_EVERY_OVERRIDE:-$SUMMARY_EVERY_DEFAULT}
  local seed=$((SEED_BASE + nx + steps))

  local persistent_active=0
  case "$mode" in
    cpu_baseline) persistent_active=0 ;;
    persistent_active_path_0241) persistent_active=1 ;;
    *) echo "[0241-active-path] ERROR: unknown mode $mode" >&2; return 2 ;;
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
      MPCD_CUDA_RESAMPLING_PERSISTENT_0240="$persistent_active" \
      MPCD_CUDA_RESAMPLING_PERSISTENT_0240_MIN_PARTICLES=0 \
      MPCD_CUDA_RESAMPLING_PERSISTENT_ACTIVE_PATH_0241_STRICT=1 \
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

for spec in $GRID_CASES; do
  IFS=: read -r nx steps <<<"$spec"
  ny=${NY_OVERRIDE:-$nx}
  grid="${nx}x${ny}_s${steps}"
  base_root="runs/cuda_resampling_persistent_active_path_0241_cpu_baseline_${grid}"
  base_stdout="$ART_DIR/cuda_resampling_persistent_active_path_0241_cpu_baseline_${grid}.stdout.log"
  base_stderr="$ART_DIR/cuda_resampling_persistent_active_path_0241_cpu_baseline_${grid}.stderr.log"
  echo "[0241-active-path] running baseline $grid"
  run_validation_logged "$nx" "$ny" "$steps" "$base_root" "cuda0241_cpu_baseline_${grid}" cpu_baseline "$base_stdout" "$base_stderr"
  base_rc=$?
  base_wall=$(summary_wall "$base_root/validation_summary_0162.csv")
  printf '%s,%s,%s,%s,cpu_baseline,%s,%s,%s,0,1,0,0,%s,%s,%s,none,none\n' \
    "$grid" "$nx" "$ny" "$steps" "$base_rc" "$base_wall" "$base_wall" \
    "$([[ $base_rc -eq 0 ]] && echo PASS || echo FAIL)" "$base_stdout" "$base_stderr" >> "$OUT_CSV"

  run_root="runs/cuda_resampling_persistent_active_path_0241_${grid}"
  stdout_log="$ART_DIR/cuda_resampling_persistent_active_path_0241_${grid}.stdout.log"
  stderr_log="$ART_DIR/cuda_resampling_persistent_active_path_0241_${grid}.stderr.log"
  compare_csv="$ART_DIR/cuda_resampling_persistent_active_path_compare_0241_${grid}.csv"
  compare_summary="$ART_DIR/cuda_resampling_persistent_active_path_compare_summary_0241_${grid}.csv"
  echo "[0241-active-path] running persistent_active_path_0241 $grid"
  run_validation_logged "$nx" "$ny" "$steps" "$run_root" "cuda0241_active_${grid}" persistent_active_path_0241 "$stdout_log" "$stderr_log"
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
print(f"$grid,$nx,$ny,$steps,persistent_active_path_0241,$rc,{base},{wall},{delta},{speed},$failed,$compared,$verdict,$stdout_log,$stderr_log,$compare_csv,$compare_summary")
PY
  echo "[0241-active-path] $verdict $grid: wall=$wall baseline=$base_wall failed=$failed/$compared"
  if [[ "$STOP_ON_FAIL" == "1" && ( "$rc" != "0" || "$failed" != "0" || "$verdict" != "PASS" ) ]]; then
    exit 1
  fi
done

echo "[0241-active-path] wrote $OUT_CSV"
