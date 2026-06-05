#!/usr/bin/env bash
set -euo pipefail

# 0234 — real-state CUDA resampling shadow transfer harness.
# It runs a CPU baseline and a CUDA shadow-transfer run.  The CUDA pass is not
# active in the simulation dynamics: it mutates only temporary copies built from
# the real resampling donor-particle selection and writes conservation diagnostics.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BIN=${BIN:-build/src_mpcd_base_cuda_0234}
ART_DIR=${ART_DIR:-dev_history/artifacts/gpu_cuda_resampling_0234}
GRID_CASES=${GRID_CASES:-"64:200 128:100"}
GAMMA=${GAMMA:-20}
THREADS=${THREADS:-8}
SUMMARY_EVERY_DEFAULT=${SUMMARY_EVERY:-50}
SEED_BASE=${SEED_BASE:-1620234}
CASE_LIST=${CASE_LIST:-tg_periodic_full}
PROJECTION_BACKEND=${PROJECTION_BACKEND:-cpu}
PROJECTION_ENABLE=${PROJECTION_ENABLE:-false}
STRICT_SHADOW=${STRICT_SHADOW:-0}
COMPARE_PLAN=${COMPARE_PLAN:-0}
TRANSFER_STRICT=${TRANSFER_STRICT:-0}
TRANSFER_MAX_TRANSFERS=${TRANSFER_MAX_TRANSFERS:-4096}
STOP_ON_FAIL=${STOP_ON_FAIL:-1}
MODES=${MODES:-"cpu_baseline cuda_resampling_transfer_shadow"}

mkdir -p "$ART_DIR"

if [[ ! -x "$BIN" ]]; then
  OUT="$BIN" CUDA_ARCH_FLAGS=${CUDA_ARCH_FLAGS:-} bash scripts/build_src_mpcd_cuda_0234.sh
fi
if [[ ! -x "$BIN" ]]; then
  echo "[0234-resampling-transfer-shadow] ERROR: missing binary $BIN" >&2
  exit 127
fi

OUT_CSV=${OUT_CSV:-$ART_DIR/cuda_resampling_transfer_shadow_0234.csv}
printf 'grid,NX,NY,steps,mode,runExitCode,baselineWallTime,modeWallTime,wallDelta_s,wallSpeedup,failed_metrics,compared_metrics,verdict,guardRows,guardPassRows,transferRows,transferPassRows,transferCellMismatch,transferRoleMismatch,transferMassMaxAbs,transferVxMaxAbs,transferVyMaxAbs,transferMassConservationMaxAbs,transferPxConservationMaxAbs,transferPyConservationMaxAbs,shadowTransfersMax,actualMassMax,guardCsv,transferCsv,compareCsv,compareSummary,stdoutLog,stderrLog\n' > "$OUT_CSV"

run_validation_logged() {
  local nx=$1 ny=$2 steps=$3 root=$4 tag=$5 guard=$6 transfer=$7 guard_csv=$8 transfer_csv=$9 stdout_log=${10} stderr_log=${11}
  local summary_every=${SUMMARY_EVERY_OVERRIDE:-$SUMMARY_EVERY_DEFAULT}
  local seed=$((SEED_BASE + nx + steps))
  set +e
  env BIN="$BIN" BUILD_IF_MISSING=0 CASE_LIST="$CASE_LIST" \
      NX="$nx" NY="$ny" GAMMA="$GAMMA" STEPS="$steps" SUMMARY_EVERY="$summary_every" \
      THREADS="$THREADS" SEED="$seed" DUMP_STATE_EVERY=0 \
      RUN_ROOT="$root" RUN_TAG="$tag" PROJECTION_BACKEND="$PROJECTION_BACKEND" PROJECTION_ENABLE="$PROJECTION_ENABLE" \
      MPCD_CUDA_RESAMPLING_SHADOW="$guard" \
      MPCD_CUDA_RESAMPLING_SHADOW_STRICT="$STRICT_SHADOW" \
      MPCD_CUDA_RESAMPLING_SHADOW_COMPARE_PLAN="$COMPARE_PLAN" \
      MPCD_CUDA_RESAMPLING_SHADOW_CSV="$guard_csv" \
      MPCD_CUDA_RESAMPLING_TRANSFER_SHADOW="$transfer" \
      MPCD_CUDA_RESAMPLING_TRANSFER_SHADOW_STRICT="$TRANSFER_STRICT" \
      MPCD_CUDA_RESAMPLING_TRANSFER_SHADOW_MAX_TRANSFERS="$TRANSFER_MAX_TRANSFERS" \
      MPCD_CUDA_RESAMPLING_TRANSFER_SHADOW_CSV="$transfer_csv" \
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
  local label=$1 nx=$2 ny=$3 steps=$4 mode=$5 run_rc=$6 base_root=$7 run_root=$8 guard_csv=$9 transfer_csv=${10} compare_csv=${11} compare_summary=${12} stdout_log=${13} stderr_log=${14}
  python3 - "$label" "$nx" "$ny" "$steps" "$mode" "$run_rc" "$base_root/validation_summary_0162.csv" "$run_root/validation_summary_0162.csv" "$guard_csv" "$transfer_csv" "$compare_csv" "$compare_summary" "$stdout_log" "$stderr_log" "$OUT_CSV" <<'PY'
import csv, math, os, sys
(label,nx,ny,steps,mode,run_rc,base_summary,run_summary,guard_csv,transfer_csv,compare_csv,compare_summary,stdout_log,stderr_log,out_csv)=sys.argv[1:16]
fields=['grid','NX','NY','steps','mode','runExitCode','baselineWallTime','modeWallTime','wallDelta_s','wallSpeedup','failed_metrics','compared_metrics','verdict','guardRows','guardPassRows','transferRows','transferPassRows','transferCellMismatch','transferRoleMismatch','transferMassMaxAbs','transferVxMaxAbs','transferVyMaxAbs','transferMassConservationMaxAbs','transferPxConservationMaxAbs','transferPyConservationMaxAbs','shadowTransfersMax','actualMassMax','guardCsv','transferCsv','compareCsv','compareSummary','stdoutLog','stderrLog']

def read_one(path, default=None):
    if path == 'none' or not os.path.exists(path):
        return default.copy() if isinstance(default, dict) else (default if default is not None else {})
    with open(path,newline='') as f:
        rows=list(csv.DictReader(f))
    if len(rows)!=1:
        return default.copy() if isinstance(default, dict) else {}
    return rows[0]

def read_rows(path):
    if path == 'none' or not os.path.exists(path): return []
    with open(path,newline='') as f: return list(csv.DictReader(f))

def f(r,k,default='nan'):
    try: return float(r.get(k,default) or default)
    except Exception: return float('nan')

def i(r,k,default='0'):
    try: return int(round(float(r.get(k,default) or default)))
    except Exception: return 0

def max_col(rows, name):
    vals=[]
    for r in rows:
        try: vals.append(abs(float(r.get(name,'0') or 0.0)))
        except Exception: pass
    return max(vals) if vals else 0.0

def sum_col(rows, name):
    return sum(i(r,name,'0') for r in rows)

base=read_one(base_summary, {'wallTime':'nan'})
run=read_one(run_summary, {'wallTime':'nan'})
cmp=read_one(compare_summary, {'failed_metrics':'999999','compared_metrics':'0'}) if compare_summary!='none' else {'failed_metrics':'0','compared_metrics':'0'}
failed=i(cmp,'failed_metrics','0'); compared=i(cmp,'compared_metrics','0')
guard=read_rows(guard_csv); transfer=read_rows(transfer_csv)
guard_pass=sum(1 for r in guard if str(r.get('pass','0')) in ('1','1.0','true','True'))
transfer_pass=sum(1 for r in transfer if str(r.get('pass','0')) in ('1','1.0','true','True'))
cell_mismatch=sum_col(transfer,'cellMismatch'); role_mismatch=sum_col(transfer,'roleMismatch')
wall=f(run,'wallTime'); bwall=f(base,'wallTime')
rc=int(run_rc)
if mode == 'cpu_baseline':
    verdict='PASS' if rc==0 else 'FAIL'
else:
    verdict='PASS' if (rc==0 and failed==0 and len(guard)>0 and guard_pass==len(guard) and len(transfer)>0 and transfer_pass==len(transfer) and cell_mismatch==0 and role_mismatch==0) else 'FAIL'
row={
 'grid':label,'NX':nx,'NY':ny,'steps':steps,'mode':mode,'runExitCode':rc,
 'baselineWallTime':bwall,'modeWallTime':wall,'wallDelta_s':wall-bwall if math.isfinite(wall) and math.isfinite(bwall) else float('nan'),
 'wallSpeedup':bwall/wall if wall and wall>0 and math.isfinite(bwall) else float('nan'),
 'failed_metrics':failed,'compared_metrics':compared,'verdict':verdict,
 'guardRows':len(guard),'guardPassRows':guard_pass,
 'transferRows':len(transfer),'transferPassRows':transfer_pass,
 'transferCellMismatch':cell_mismatch,'transferRoleMismatch':role_mismatch,
 'transferMassMaxAbs':max_col(transfer,'massMaxAbs'),
 'transferVxMaxAbs':max_col(transfer,'vxMaxAbs'),
 'transferVyMaxAbs':max_col(transfer,'vyMaxAbs'),
 'transferMassConservationMaxAbs':max_col(transfer,'massConservationAbs'),
 'transferPxConservationMaxAbs':max_col(transfer,'pxConservationAbs'),
 'transferPyConservationMaxAbs':max_col(transfer,'pyConservationAbs'),
 'shadowTransfersMax':max_col(transfer,'shadowTransfers'),
 'actualMassMax':max_col(transfer,'actualMass'),
 'guardCsv':guard_csv,'transferCsv':transfer_csv,'compareCsv':compare_csv,'compareSummary':compare_summary,
 'stdoutLog':stdout_log,'stderrLog':stderr_log}
with open(out_csv,'a',newline='') as fcsv:
    csv.DictWriter(fcsv,fieldnames=fields).writerow(row)
print(f"[0234-resampling-transfer-shadow] {verdict} {label}/{mode}: rc={rc} wall={wall:.6g}s baseline={bwall:.6g}s guardRows={len(guard)} transferRows={len(transfer)} transferPass={transfer_pass} cellMismatch={cell_mismatch} roleMismatch={role_mismatch} failed={failed}/{compared}")
if verdict!='PASS': raise SystemExit(1)
PY
}

fail_count=0
for spec in $GRID_CASES; do
  IFS=: read -r nx steps <<< "$spec"
  [[ -n "${nx:-}" && -n "${steps:-}" ]] || { echo "[0234-resampling-transfer-shadow] invalid GRID_CASES entry $spec" >&2; exit 2; }
  ny=${NY_OVERRIDE:-$nx}
  label="${nx}x${ny}_s${steps}"
  base_root="runs/cuda_resampling_transfer_shadow_0234_cpu_${label}"
  shadow_root="runs/cuda_resampling_transfer_shadow_0234_shadow_${label}"

  if [[ "$MODES" == *"cpu_baseline"* ]]; then
    stdout_log="$ART_DIR/cuda_resampling_transfer_shadow_0234_cpu_${label}.stdout.log"
    stderr_log="$ART_DIR/cuda_resampling_transfer_shadow_0234_cpu_${label}.stderr.log"
    echo "[0234-resampling-transfer-shadow] running baseline $label"
    run_validation_logged "$nx" "$ny" "$steps" "$base_root" "cuda0234_cpu_${label}" 0 0 "none" "none" "$stdout_log" "$stderr_log"; rc=$?
    if ! append_summary "$label" "$nx" "$ny" "$steps" "cpu_baseline" "$rc" "$base_root" "$base_root" "none" "none" "none" "none" "$stdout_log" "$stderr_log"; then
      fail_count=$((fail_count+1)); [[ "$STOP_ON_FAIL" == "1" ]] && exit 1
    fi
  fi

  if [[ "$MODES" == *"cuda_resampling_transfer_shadow"* ]]; then
    guard_csv="$ART_DIR/cuda_resampling_guard_shadow_detail_0234_${label}.csv"
    transfer_csv="$ART_DIR/cuda_resampling_transfer_shadow_detail_0234_${label}.csv"
    compare_csv="$ART_DIR/cuda_resampling_transfer_shadow_compare_0234_${label}.csv"
    compare_summary="$ART_DIR/cuda_resampling_transfer_shadow_compare_summary_0234_${label}.csv"
    stdout_log="$ART_DIR/cuda_resampling_transfer_shadow_0234_shadow_${label}.stdout.log"
    stderr_log="$ART_DIR/cuda_resampling_transfer_shadow_0234_shadow_${label}.stderr.log"
    rm -f "$guard_csv" "$transfer_csv" "$compare_csv" "$compare_summary"
    echo "[0234-resampling-transfer-shadow] running transfer shadow $label"
    run_validation_logged "$nx" "$ny" "$steps" "$shadow_root" "cuda0234_shadow_${label}" 1 1 "$guard_csv" "$transfer_csv" "$stdout_log" "$stderr_log"; rc=$?
    compare_if_possible "$base_root" "$shadow_root" "$compare_csv" "$compare_summary" "$stdout_log" "$stderr_log" || true
    if ! append_summary "$label" "$nx" "$ny" "$steps" "cuda_resampling_transfer_shadow" "$rc" "$base_root" "$shadow_root" "$guard_csv" "$transfer_csv" "$compare_csv" "$compare_summary" "$stdout_log" "$stderr_log"; then
      fail_count=$((fail_count+1)); [[ "$STOP_ON_FAIL" == "1" ]] && exit 1
    fi
  fi
done

echo "[0234-resampling-transfer-shadow] wrote $OUT_CSV"
if [[ $fail_count -ne 0 ]]; then
  echo "[0234-resampling-transfer-shadow] completed with $fail_count failing row(s); see $OUT_CSV" >&2
  exit 1
fi
