#!/usr/bin/env bash
set -euo pipefail

# 0231 — robust harness for CUDA resampling shadow on real deposits.
# The shadow pass criterion now validates classification/aggregate invariants by default; CPU-specific transfer-plan mass differences are recorded but not fatal.
#
# Design:
#   - always writes one row per requested mode;
#   - captures stdout/stderr for baseline and shadow;
#   - runs shadow with strict=0 by default, so CUDA/CPU mismatches are recorded
#     in the shadow CSV instead of aborting before analysis;
#   - marks shadow verdict FAIL if shadowRows==0, even when dynamics compare PASS.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BIN=${BIN:-build/src_mpcd_base_cuda_0231}
ART_DIR=${ART_DIR:-dev_history/artifacts/gpu_cuda_resampling_0231}
GRID_CASES=${GRID_CASES:-"64:200 128:100"}
GAMMA=${GAMMA:-20}
THREADS=${THREADS:-8}
SUMMARY_EVERY_DEFAULT=${SUMMARY_EVERY:-50}
SEED_BASE=${SEED_BASE:-1620231}
CASE_LIST=${CASE_LIST:-tg_periodic_full}
PROJECTION_BACKEND=${PROJECTION_BACKEND:-cpu}
PROJECTION_ENABLE=${PROJECTION_ENABLE:-false}
# Use non-strict shadow by default so mismatch details are written and the run
# reaches the post-processing section. Set STRICT_SHADOW=1 to make the simulation
# abort on first CUDA/CPU shadow mismatch.
STRICT_SHADOW=${STRICT_SHADOW:-0}
# The CPU production resampling planner is local/geometric. The CUDA diagnostic
# planner is intentionally simpler and may produce a different planned mass even
# when poor/rich classification and aggregate deficit/excess are identical. Set
# COMPARE_PLAN=1 only for synthetic planner-equivalence tests.
COMPARE_PLAN=${COMPARE_PLAN:-0}
STOP_ON_FAIL=${STOP_ON_FAIL:-1}
MODES=${MODES:-"cpu_baseline cuda_resampling_shadow"}

mkdir -p "$ART_DIR"

if [[ ! -x "$BIN" ]]; then
  OUT="$BIN" CUDA_ARCH_FLAGS=${CUDA_ARCH_FLAGS:-} bash scripts/build_src_mpcd_cuda_0231.sh
fi
if [[ ! -x "$BIN" ]]; then
  echo "[0231-resampling-shadow] ERROR: missing binary $BIN" >&2
  exit 127
fi

OUT_CSV=${OUT_CSV:-$ART_DIR/cuda_resampling_shadow_0231.csv}
printf 'grid,NX,NY,steps,mode,runExitCode,baselineWallTime,modeWallTime,wallDelta_s,wallSpeedup,failed_metrics,compared_metrics,verdict,shadowRows,shadowPassRows,shadowPoorMismatch,shadowRichMismatch,shadowDeficitAbsDiffMax,shadowExcessAbsDiffMax,shadowPlannedAbsDiffMax,shadowCsv,compareCsv,compareSummary,stdoutLog,stderrLog\n' > "$OUT_CSV"

run_validation_logged() {
  local nx=$1 ny=$2 steps=$3 root=$4 tag=$5 shadow=$6 shadow_csv=$7 stdout_log=$8 stderr_log=$9
  local summary_every=${SUMMARY_EVERY_OVERRIDE:-$SUMMARY_EVERY_DEFAULT}
  local seed=$((SEED_BASE + nx + steps))
  set +e
  env BIN="$BIN" BUILD_IF_MISSING=0 CASE_LIST="$CASE_LIST" \
      NX="$nx" NY="$ny" GAMMA="$GAMMA" STEPS="$steps" SUMMARY_EVERY="$summary_every" \
      THREADS="$THREADS" SEED="$seed" DUMP_STATE_EVERY=0 \
      RUN_ROOT="$root" RUN_TAG="$tag" PROJECTION_BACKEND="$PROJECTION_BACKEND" PROJECTION_ENABLE="$PROJECTION_ENABLE" \
      MPCD_CUDA_RESAMPLING_SHADOW="$shadow" \
      MPCD_CUDA_RESAMPLING_SHADOW_STRICT="$STRICT_SHADOW" \
      MPCD_CUDA_RESAMPLING_SHADOW_COMPARE_PLAN="$COMPARE_PLAN" \
      MPCD_CUDA_RESAMPLING_SHADOW_CSV="$shadow_csv" \
      bash scripts/run_validation_mono_config_0162.sh >"$stdout_log" 2>"$stderr_log"
  local rc=$?
  set -e
  return $rc
}

compare_if_possible() {
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

append_summary() {
  local label=$1 nx=$2 ny=$3 steps=$4 mode=$5 run_rc=$6 base_root=$7 run_root=$8 shadow_csv=$9 compare_csv=${10} compare_summary=${11} stdout_log=${12} stderr_log=${13}
  python3 - "$label" "$nx" "$ny" "$steps" "$mode" "$run_rc" "$base_root/validation_summary_0162.csv" "$run_root/validation_summary_0162.csv" "$shadow_csv" "$compare_csv" "$compare_summary" "$stdout_log" "$stderr_log" "$OUT_CSV" <<'PY'
import csv, math, os, sys
(label,nx,ny,steps,mode,run_rc,base_summary,run_summary,shadow_csv,compare_csv,compare_summary,stdout_log,stderr_log,out_csv)=sys.argv[1:15]
fields=['grid','NX','NY','steps','mode','runExitCode','baselineWallTime','modeWallTime','wallDelta_s','wallSpeedup','failed_metrics','compared_metrics','verdict','shadowRows','shadowPassRows','shadowPoorMismatch','shadowRichMismatch','shadowDeficitAbsDiffMax','shadowExcessAbsDiffMax','shadowPlannedAbsDiffMax','shadowCsv','compareCsv','compareSummary','stdoutLog','stderrLog']

def read_one(path, default=None):
    if path == 'none' or not os.path.exists(path):
        return default.copy() if isinstance(default, dict) else (default if default is not None else {})
    with open(path,newline='') as f:
        rows=list(csv.DictReader(f))
    if len(rows)!=1:
        return default.copy() if isinstance(default, dict) else {}
    return rows[0]

def f(r,k,default='nan'):
    try: return float(r.get(k,default) or default)
    except Exception: return float('nan')

def i(r,k,default='0'):
    try: return int(round(float(r.get(k,default) or default)))
    except Exception: return 0

base=read_one(base_summary, {'wallTime':'nan'})
run=read_one(run_summary, {'wallTime':'nan'})
cmp=read_one(compare_summary, {'failed_metrics':'999999','compared_metrics':'0'}) if compare_summary!='none' else {'failed_metrics':'0','compared_metrics':'0'}
failed=i(cmp,'failed_metrics','0'); compared=i(cmp,'compared_metrics','0')
shadow_rows=[]
if shadow_csv != 'none' and os.path.exists(shadow_csv):
    with open(shadow_csv,newline='') as fp:
        shadow_rows=list(csv.DictReader(fp))

def max_float(name):
    vals=[]
    for r in shadow_rows:
        try: vals.append(abs(float(r.get(name,'0') or 0.0)))
        except Exception: pass
    return max(vals) if vals else 0.0
shadow_poor=sum(i(r,'poorMismatch','0') for r in shadow_rows)
shadow_rich=sum(i(r,'richMismatch','0') for r in shadow_rows)
shadow_pass=sum(1 for r in shadow_rows if str(r.get('pass','0')) in ('1','1.0','true','True'))
wall=f(run,'wallTime'); bwall=f(base,'wallTime')
rc=int(run_rc)
if mode == 'cpu_baseline':
    verdict = 'PASS' if rc == 0 else 'FAIL'
else:
    verdict = 'PASS' if (rc == 0 and failed == 0 and len(shadow_rows) > 0 and shadow_pass == len(shadow_rows) and shadow_poor == 0 and shadow_rich == 0) else 'FAIL'
row={
 'grid':label,'NX':nx,'NY':ny,'steps':steps,'mode':mode,'runExitCode':rc,
 'baselineWallTime':bwall,'modeWallTime':wall,'wallDelta_s':wall-bwall if math.isfinite(wall) and math.isfinite(bwall) else float('nan'),
 'wallSpeedup':bwall/wall if wall and wall>0 and math.isfinite(bwall) else float('nan'),
 'failed_metrics':failed,'compared_metrics':compared,'verdict':verdict,
 'shadowRows':len(shadow_rows),'shadowPassRows':shadow_pass,
 'shadowPoorMismatch':shadow_poor,'shadowRichMismatch':shadow_rich,
 'shadowDeficitAbsDiffMax':max_float('deficitAbsDiff'),
 'shadowExcessAbsDiffMax':max_float('excessAbsDiff'),
 'shadowPlannedAbsDiffMax':max_float('plannedAbsDiff'),
 'shadowCsv':shadow_csv,'compareCsv':compare_csv,'compareSummary':compare_summary,
 'stdoutLog':stdout_log,'stderrLog':stderr_log}
with open(out_csv,'a',newline='') as fcsv:
    csv.DictWriter(fcsv,fieldnames=fields).writerow(row)
print(f"[0231-resampling-shadow] {verdict} {label}/{mode}: rc={rc} wall={wall:.6g}s baseline={bwall:.6g}s shadowRows={len(shadow_rows)} shadowPass={shadow_pass} poorMismatch={shadow_poor} richMismatch={shadow_rich} failed={failed}/{compared}")
if verdict!='PASS':
    raise SystemExit(1)
PY
}

fail_count=0
for spec in $GRID_CASES; do
  IFS=: read -r nx steps <<< "$spec"
  [[ -n "${nx:-}" && -n "${steps:-}" ]] || { echo "[0231-resampling-shadow] invalid GRID_CASES entry $spec" >&2; exit 2; }
  ny=${NY_OVERRIDE:-$nx}
  label="${nx}x${ny}_s${steps}"
  base_root="runs/cuda_resampling_shadow_0231_cpu_baseline_${label}"
  shadow_root="runs/cuda_resampling_shadow_0231_shadow_${label}"

  if [[ "$MODES" == *"cpu_baseline"* ]]; then
    stdout_log="$ART_DIR/cuda_resampling_shadow_0231_cpu_${label}.stdout.log"
    stderr_log="$ART_DIR/cuda_resampling_shadow_0231_cpu_${label}.stderr.log"
    echo "[0231-resampling-shadow] running baseline $label"
    run_validation_logged "$nx" "$ny" "$steps" "$base_root" "cuda0231_cpu_${label}" 0 "none" "$stdout_log" "$stderr_log"; rc=$?
    if ! append_summary "$label" "$nx" "$ny" "$steps" "cpu_baseline" "$rc" "$base_root" "$base_root" "none" "none" "none" "$stdout_log" "$stderr_log"; then
      fail_count=$((fail_count+1))
      [[ "$STOP_ON_FAIL" == "1" ]] && exit 1
    fi
  fi

  if [[ "$MODES" == *"cuda_resampling_shadow"* ]]; then
    shadow_csv="$ART_DIR/cuda_resampling_shadow_detail_0231_${label}.csv"
    compare_csv="$ART_DIR/cuda_resampling_shadow_compare_0231_${label}.csv"
    compare_summary="$ART_DIR/cuda_resampling_shadow_compare_summary_0231_${label}.csv"
    stdout_log="$ART_DIR/cuda_resampling_shadow_0231_shadow_${label}.stdout.log"
    stderr_log="$ART_DIR/cuda_resampling_shadow_0231_shadow_${label}.stderr.log"
    rm -f "$shadow_csv" "$compare_csv" "$compare_summary"
    echo "[0231-resampling-shadow] running shadow $label"
    run_validation_logged "$nx" "$ny" "$steps" "$shadow_root" "cuda0231_shadow_${label}" 1 "$shadow_csv" "$stdout_log" "$stderr_log"; rc=$?
    compare_if_possible "$base_root" "$shadow_root" "$compare_csv" "$compare_summary" "$stdout_log" "$stderr_log" || true
    if ! append_summary "$label" "$nx" "$ny" "$steps" "cuda_resampling_shadow" "$rc" "$base_root" "$shadow_root" "$shadow_csv" "$compare_csv" "$compare_summary" "$stdout_log" "$stderr_log"; then
      fail_count=$((fail_count+1))
      [[ "$STOP_ON_FAIL" == "1" ]] && exit 1
    fi
  fi

done

echo "[0231-resampling-shadow] wrote $OUT_CSV"
if [[ $fail_count -ne 0 ]]; then
  echo "[0231-resampling-shadow] completed with $fail_count failing row(s); see $OUT_CSV and logs in $ART_DIR" >&2
  exit 1
fi
