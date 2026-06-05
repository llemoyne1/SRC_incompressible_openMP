#!/usr/bin/env bash
set -euo pipefail

# 0237 — active CUDA extraction+insertion stages for weighted resampling.
# CPU classification, transfer planning and donor/receiver selection remain
# authoritative.  CUDA can replace extraction role changes, insertion writes, or
# both, so the harness measures them separately.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BIN=${BIN:-build/src_mpcd_base_cuda_0237}
ART_DIR=${ART_DIR:-dev_history/artifacts/gpu_cuda_resampling_0237}
GRID_CASES=${GRID_CASES:-"64:200 128:100"}
GAMMA=${GAMMA:-20}
THREADS=${THREADS:-8}
SUMMARY_EVERY_DEFAULT=${SUMMARY_EVERY:-50}
SEED_BASE=${SEED_BASE:-1620237}
CASE_LIST=${CASE_LIST:-tg_periodic_full}
PROJECTION_BACKEND=${PROJECTION_BACKEND:-cpu}
PROJECTION_ENABLE=${PROJECTION_ENABLE:-false}
STOP_ON_FAIL=${STOP_ON_FAIL:-1}
MODES=${MODES:-"cpu_baseline cuda_resampling_extraction cuda_resampling_insertion cuda_resampling_extract_insert"}

mkdir -p "$ART_DIR"

if [[ ! -x "$BIN" ]]; then
  OUT="$BIN" CUDA_ARCH_FLAGS=${CUDA_ARCH_FLAGS:-} bash scripts/build_src_mpcd_cuda_0237.sh
fi
if [[ ! -x "$BIN" ]]; then
  echo "[0237-resampling-extract-insert] ERROR: missing binary $BIN" >&2
  exit 127
fi

OUT_CSV=${OUT_CSV:-$ART_DIR/cuda_resampling_extraction_insertion_active_0237.csv}
printf 'grid,NX,NY,steps,mode,runExitCode,baselineWallTime,modeWallTime,wallDelta_s,wallSpeedup,failed_metrics,compared_metrics,verdict,compareCsv,compareSummary,stdoutLog,stderrLog\n' > "$OUT_CSV"

run_validation_logged() {
  local nx=$1 ny=$2 steps=$3 root=$4 tag=$5 use_extract=$6 use_insert=$7 stdout_log=$8 stderr_log=$9
  local summary_every=${SUMMARY_EVERY_OVERRIDE:-$SUMMARY_EVERY_DEFAULT}
  local seed=$((SEED_BASE + nx + steps))
  set +e
  env BIN="$BIN" BUILD_IF_MISSING=0 CASE_LIST="$CASE_LIST" \
      NX="$nx" NY="$ny" GAMMA="$GAMMA" STEPS="$steps" SUMMARY_EVERY="$summary_every" \
      THREADS="$THREADS" SEED="$seed" DUMP_STATE_EVERY=0 \
      RUN_ROOT="$root" RUN_TAG="$tag" PROJECTION_BACKEND="$PROJECTION_BACKEND" PROJECTION_ENABLE="$PROJECTION_ENABLE" \
      MPCD_CUDA_RESAMPLING_EXTRACTION_USE="$use_extract" \
      MPCD_CUDA_RESAMPLING_EXTRACTION_STRICT=1 \
      MPCD_CUDA_RESAMPLING_INSERTION_USE="$use_insert" \
      MPCD_CUDA_RESAMPLING_INSERTION_STRICT=1 \
      bash scripts/run_validation_mono_config_0162.sh >"$stdout_log" 2>"$stderr_log"
  local rc=$?
  set -e
  return $rc
}

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
            if k in r and r[k] != '': failed=int(float(r[k])); break
        for k in ('compared_metrics','compared','nCompared'):
            if k in r and r[k] != '': compared=int(float(r[k])); break
        verdict = r.get('verdict', 'PASS' if failed==0 else 'FAIL')
except Exception:
    pass
print(f'{failed},{compared},{verdict}')
PY
}

for spec in $GRID_CASES; do
  IFS=: read -r nx steps <<<"$spec"
  ny=$nx
  grid="${nx}x${ny}_s${steps}"
  base_root="runs/cuda_resampling_extract_insert_0237_baseline_${grid}"
  base_stdout="$ART_DIR/cuda_resampling_extract_insert_0237_baseline_${grid}.stdout.log"
  base_stderr="$ART_DIR/cuda_resampling_extract_insert_0237_baseline_${grid}.stderr.log"
  echo "[0237-resampling-extract-insert] running baseline $grid"
  run_validation_logged "$nx" "$ny" "$steps" "$base_root" "cuda0237_baseline" 0 0 "$base_stdout" "$base_stderr"
  base_rc=$?
  base_wall=$(summary_wall "$base_root/validation_summary_0162.csv")
  printf '%s,%s,%s,%s,cpu_baseline,%s,%s,%s,0,1,0,0,%s,none,none,%s,%s\n' \
    "$grid" "$nx" "$ny" "$steps" "$base_rc" "$base_wall" "$base_wall" \
    "$([[ $base_rc -eq 0 ]] && echo PASS || echo FAIL)" "$base_stdout" "$base_stderr" >> "$OUT_CSV"

  for mode in $MODES; do
    [[ "$mode" == "cpu_baseline" ]] && continue
    case "$mode" in
      cuda_resampling_extraction) use_extract=1; use_insert=0 ;;
      cuda_resampling_insertion) use_extract=0; use_insert=1 ;;
      cuda_resampling_extract_insert) use_extract=1; use_insert=1 ;;
      *) echo "[0237-resampling-extract-insert] unknown mode $mode" >&2; exit 2 ;;
    esac
    run_root="runs/cuda_resampling_extract_insert_0237_${mode}_${grid}"
    stdout_log="$ART_DIR/cuda_resampling_extract_insert_0237_${mode}_${grid}.stdout.log"
    stderr_log="$ART_DIR/cuda_resampling_extract_insert_0237_${mode}_${grid}.stderr.log"
    compare_csv="$ART_DIR/cuda_resampling_extract_insert_compare_0237_${mode}_${grid}.csv"
    compare_summary="$ART_DIR/cuda_resampling_extract_insert_compare_summary_0237_${mode}_${grid}.csv"
    echo "[0237-resampling-extract-insert] running $mode $grid"
    run_validation_logged "$nx" "$ny" "$steps" "$run_root" "cuda0237_${mode}" "$use_extract" "$use_insert" "$stdout_log" "$stderr_log"
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
print(f"$grid,$nx,$ny,$steps,$mode,$rc,{base},{wall},{delta},{speed},$failed,$compared,$verdict,$compare_csv,$compare_summary,$stdout_log,$stderr_log")
PY
    echo "[0237-resampling-extract-insert] $verdict $grid/$mode: wall=$wall baseline=$base_wall speedup=$(python3 - <<PY
b=float('$base_wall') if '$base_wall' != 'nan' else float('nan')
w=float('$wall') if '$wall' != 'nan' else float('nan')
print(b/w if w>0 else float('nan'))
PY
) failed=$failed/$compared"
    if [[ "$STOP_ON_FAIL" == "1" && ( "$rc" != "0" || "$failed" != "0" || "$verdict" != "PASS" ) ]]; then
      exit 1
    fi
  done
done

echo "[0237-resampling-extract-insert] wrote $OUT_CSV"
