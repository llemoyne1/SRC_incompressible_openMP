#!/usr/bin/env bash
set -euo pipefail

# 0295 — passive post-SRC CUDA support survey validation.
#
# This runner validates the 0295 survey for what it is: a non-mutating observer
# of the current CUDA SRC classic path.  It therefore runs each current CUDA
# demo twice:
#   1. survey disabled;
#   2. survey enabled.
# It then compares the two CUDA summaries directly.  It deliberately does not
# reuse older CPU-vs-CUDA work-package validators such as 0264/0280c, because
# those validators test historical backend equivalence and can fail in
# survey_off before the 0295 module is even exercised.
#
# Scope:
#   SRC classic CUDA resident -> post-SRC survey on physical non-shifted grid.
#   Q6/resampling/virial remain disabled in the demo scripts.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BIN=${BIN:-build/src_mpcd_base_cuda_0295}
ART_DIR=${ART_DIR:-dev_history/artifacts/gpu_cuda_resampling_survey_0295}
NX=${NX:-64}
NY=${NY:-64}
GAMMA=${GAMMA:-20}
STEPS=${STEPS:-80}
THREADS=${THREADS:-8}
SURVEY_EVERY=${SURVEY_EVERY:-10}
# Active inlet/outlet + immersed-circle VK is not part of the default strict
# 0295 suite because the thermostat-enabled case is not bit-reproducible OFF/OFF.
# It remains available as an optional diagnostic/stress test with RUN_VK=1.
# When enabled, keep the survey summary-aligned and the thermostat disabled by
# default for strict non-mutation checks.  Set VK_THERMOSTAT_ENABLE=1 only for a
# non-verdict stress run.
VK_SURVEY_EVERY=${VK_SURVEY_EVERY:-$STEPS}
VK_THERMOSTAT_ENABLE=${VK_THERMOSTAT_ENABLE:-0}
FORCE_REBUILD=${FORCE_REBUILD:-1}
STOP_ON_FAIL=${STOP_ON_FAIL:-1}
COMPARE_ABS_TOL=${COMPARE_ABS_TOL:-1e-10}
COMPARE_REL_TOL=${COMPARE_REL_TOL:-1e-9}
RUN_TG=${RUN_TG:-1}
RUN_POISEUILLE=${RUN_POISEUILLE:-1}
RUN_STEP=${RUN_STEP:-1}
RUN_SEGMENTED=${RUN_SEGMENTED:-1}
RUN_VK=${RUN_VK:-0}

# Keep short validations cheap and deterministic.  The demo helper requires at
# least one dump, so dump at the final step only.
SUMMARY_EVERY=${SUMMARY_EVERY:-$STEPS}
DUMP_STATE_EVERY=${DUMP_STATE_EVERY:-$STEPS}
LIVE_PROGRESS=${LIVE_PROGRESS:-0}
CLEAN_RUN_ROOT=${CLEAN_RUN_ROOT:-1}
AUTO_BUILD=${AUTO_BUILD:-0}

mkdir -p "$ART_DIR"

if [[ "$FORCE_REBUILD" != "0" && "$FORCE_REBUILD" != "false" && "$FORCE_REBUILD" != "FALSE" ]]; then
  echo "[0295-survey] rebuilding $BIN"
  OUT="$BIN" CUDA_ARCH_FLAGS="${CUDA_ARCH_FLAGS:-}" bash scripts/build_src_mpcd_cuda_0295.sh
elif [[ ! -x "$BIN" ]]; then
  OUT="$BIN" CUDA_ARCH_FLAGS="${CUDA_ARCH_FLAGS:-}" bash scripts/build_src_mpcd_cuda_0295.sh
fi
if [[ ! -x "$BIN" ]]; then
  echo "[0295-survey] ERROR: missing binary $BIN" >&2
  exit 127
fi

OUT_CSV=${OUT_CSV:-$ART_DIR/cuda_resampling_survey_0295_manifest.csv}
printf 'caseName,surveyOffRoot,surveyOnRoot,offExitCode,onExitCode,comparedMetrics,failedMetrics,verdict,surveyOffFiles,surveyOffRows,surveyOnFiles,surveyOnRows,compareCsv\n' > "$OUT_CSV"

append_row() {
  python3 - "$OUT_CSV" "$@" <<'PY'
import csv, sys
out=sys.argv[1]
with open(out, 'a', newline='') as fh:
    csv.writer(fh).writerow(sys.argv[2:])
PY
}

survey_count() {
  local root=$1
  python3 - "$root" <<'PY'
import glob, os, sys
files=glob.glob(os.path.join(sys.argv[1], '**', 'cuda_resampling_support_survey_0295.csv'), recursive=True)
rows=0
for p in files:
    try:
        with open(p, newline='') as fh:
            rows += max(0, sum(1 for _ in fh) - 1)
    except FileNotFoundError:
        pass
print(f"{len(files)},{rows}")
PY
}

compare_summaries() {
  local off_summary=$1 on_summary=$2 out_csv=$3 abs_tol=$4 rel_tol=$5
  python3 - "$off_summary" "$on_summary" "$out_csv" "$abs_tol" "$rel_tol" <<'PY'
import csv, math, os, sys
from pathlib import Path

off_path, on_path, out_path, abs_tol_s, rel_tol_s = sys.argv[1:6]
abs_tol=float(abs_tol_s); rel_tol=float(rel_tol_s)

# These fields are expected to differ, be timing-only, or be file/log related.
EXCLUDE_EXACT = {
    'wallTime', 'wallTime_s', 'elapsed_s', 'elapsedSeconds', 'totalSeconds',
    'uploadSeconds', 'kernelSeconds', 'downloadSeconds', 'phaseSeconds',
    'numThreadsUsed', 'threads', 'outputDir', 'dumpPath', 'runTag', 'case',
}
EXCLUDE_SUBSTR = (
    'wall', 'elapsed', 'seconds', 'time_s', 'runtime', 'speedup',
    'profile', 'log', 'path', 'file', 'dir', 'csv',
)


def load_last(path):
    with open(path, newline='') as fh:
        rows=list(csv.DictReader(fh))
    if not rows:
        raise SystemExit(f'empty summary: {path}')
    return rows[-1]


def is_excluded(k):
    kl=k.strip().lower()
    if k in EXCLUDE_EXACT or kl in {x.lower() for x in EXCLUDE_EXACT}:
        return True
    return any(s in kl for s in EXCLUDE_SUBSTR)


def as_float(v):
    if v is None or v == '':
        return None
    try:
        x=float(v)
    except Exception:
        return None
    return x


def same_float(a,b):
    if math.isnan(a) and math.isnan(b):
        return True
    if math.isinf(a) or math.isinf(b):
        return a == b
    d=abs(a-b)
    scale=max(abs(a),abs(b),1.0)
    return d <= abs_tol + rel_tol*scale

ro=load_last(off_path); rn=load_last(on_path)
keys=[k for k in ro.keys() if k in rn and not is_excluded(k)]
rows=[]; failed=0; compared=0
for k in keys:
    vo=(ro.get(k) or '').strip(); vn=(rn.get(k) or '').strip()
    fo=as_float(vo); fn=as_float(vn)
    if fo is not None and fn is not None:
        ok=same_float(fo,fn)
        compared += 1
        if not ok: failed += 1
        rows.append({'metric':k,'off':vo,'on':vn,'absDelta': '' if (math.isnan(fo) or math.isnan(fn)) else repr(abs(fo-fn)), 'status':'PASS' if ok else 'FAIL'})
    elif vo or vn:
        # Compare non-empty non-numeric stable fields exactly.
        ok=(vo == vn)
        compared += 1
        if not ok: failed += 1
        rows.append({'metric':k,'off':vo,'on':vn,'absDelta':'', 'status':'PASS' if ok else 'FAIL'})

Path(out_path).parent.mkdir(parents=True, exist_ok=True)
with open(out_path, 'w', newline='') as fh:
    w=csv.DictWriter(fh, fieldnames=['metric','off','on','absDelta','status'])
    w.writeheader(); w.writerows(rows)
print(f'{compared},{failed},{"PASS" if compared > 0 and failed == 0 else "FAIL"}')
PY
}

run_demo_pair() {
  local case_name=$1 script=$2 nx=$3 ny=$4 steps=$5 extra_env=${6:-} survey_every=${7:-$SURVEY_EVERY}
  local case_art="$ART_DIR/$case_name"
  local off_root="$case_art/survey_off"
  local on_root="$case_art/survey_on"
  mkdir -p "$case_art"

  echo "[0295-survey] running case=$case_name survey=0 every=$survey_every script=$script"
  local off_rc=0
  set +e
  env BIN="$BIN" AUTO_BUILD=0 LIVE_PROGRESS="$LIVE_PROGRESS" CLEAN_RUN_ROOT="$CLEAN_RUN_ROOT" \
      NX="$nx" NY="$ny" GAMMA="$GAMMA" STEPS="$steps" SUMMARY_EVERY="$steps" DUMP_STATE_EVERY="$steps" \
      THREADS="$THREADS" RUN_ROOT="$off_root" \
      MPCD_CUDA_RESAMPLING_SUPPORT_SURVEY_0295=0 \
      MPCD_CUDA_RESAMPLING_SUPPORT_SURVEY_0295_EVERY="$survey_every" \
      $extra_env bash "$script" >"$case_art/survey_off.stdout.log" 2>"$case_art/survey_off.stderr.log"
  off_rc=$?
  set -e

  echo "[0295-survey] running case=$case_name survey=1 every=$survey_every script=$script"
  local on_rc=0
  set +e
  env BIN="$BIN" AUTO_BUILD=0 LIVE_PROGRESS="$LIVE_PROGRESS" CLEAN_RUN_ROOT="$CLEAN_RUN_ROOT" \
      NX="$nx" NY="$ny" GAMMA="$GAMMA" STEPS="$steps" SUMMARY_EVERY="$steps" DUMP_STATE_EVERY="$steps" \
      THREADS="$THREADS" RUN_ROOT="$on_root" \
      MPCD_CUDA_RESAMPLING_SUPPORT_SURVEY_0295=1 \
      MPCD_CUDA_RESAMPLING_SUPPORT_SURVEY_0295_EVERY="$survey_every" \
      $extra_env bash "$script" >"$case_art/survey_on.stdout.log" 2>"$case_art/survey_on.stderr.log"
  on_rc=$?
  set -e

  local off_files off_rows on_files on_rows
  IFS=, read -r off_files off_rows <<<"$(survey_count "$off_root")"
  IFS=, read -r on_files on_rows <<<"$(survey_count "$on_root")"

  local compared=0 failed=999999 verdict=FAIL
  local compare_csv="$case_art/${case_name}_survey_off_vs_on_compare.csv"
  if [[ "$off_rc" == "0" && "$on_rc" == "0" && -s "$off_root/output/summary_runtime.csv" && -s "$on_root/output/summary_runtime.csv" ]]; then
    IFS=, read -r compared failed verdict <<<"$(compare_summaries "$off_root/output/summary_runtime.csv" "$on_root/output/summary_runtime.csv" "$compare_csv" "$COMPARE_ABS_TOL" "$COMPARE_REL_TOL")"
  fi
  if [[ "$off_rc" != "0" || "$on_rc" != "0" || "$off_rows" != "0" || "$on_rows" == "0" ]]; then
    verdict=FAIL
  fi

  append_row "$case_name" "$off_root" "$on_root" "$off_rc" "$on_rc" "$compared" "$failed" "$verdict" "$off_files" "$off_rows" "$on_files" "$on_rows" "$compare_csv"
  echo "[0295-survey] case=$case_name verdict=$verdict compared=$compared failed=$failed surveyRowsOff=$off_rows surveyRowsOn=$on_rows"
  if [[ "$STOP_ON_FAIL" == "1" && "$verdict" != "PASS" ]]; then
    echo "[0295-survey] FAIL case=$case_name" >&2
    echo "[0295-survey] stdout/stderr: $case_art/survey_off.*.log $case_art/survey_on.*.log" >&2
    exit 1
  fi
}

# Common short-grid cases.  The default strict 0295 suite is intentionally limited
# to four bit-reproducible witnesses: TG, Poiseuille, backward step and segmented
# U-box.  VK is optional because the thermostat-enabled VK path is not OFF/OFF
# bit-reproducible; use RUN_VK=1 for a thermostatless strict diagnostic or
# VK_THERMOSTAT_ENABLE=1 for a non-verdict stress test.
if [[ "$RUN_TG" != "0" ]]; then
  run_demo_pair tg_periodic scripts/run_demo_src_classic_cuda_taylor_green_forced_0283.sh "$NX" "$NY" "$STEPS" "" "$SURVEY_EVERY"
fi
if [[ "$RUN_POISEUILLE" != "0" ]]; then
  run_demo_pair poiseuille_wall scripts/run_demo_src_classic_cuda_poiseuille_periodic_forced_0283.sh "$NX" "$NY" "$STEPS" "" "$SURVEY_EVERY"
fi
if [[ "$RUN_STEP" != "0" ]]; then
  run_demo_pair backward_step_io scripts/run_demo_src_classic_cuda_backward_step_io_0283.sh "$NX" "$NY" "$STEPS" "" "$SURVEY_EVERY"
fi
if [[ "$RUN_SEGMENTED" != "0" ]]; then
  run_demo_pair segmented_box_same_face scripts/run_demo_src_classic_cuda_box_same_face_io_0283.sh "$NX" "$NY" "$STEPS" "OUTLET_MODE=${SEGMENTED_OUTLET_MODE:-neumann}" "$SURVEY_EVERY"
fi
if [[ "$RUN_VK" != "0" ]]; then
  run_demo_pair von_karman_circle_io scripts/run_demo_src_classic_cuda_von_karman_cylinder_0285.sh "$NX" "$NY" "$STEPS" "UIN=${VK_UIN:-0.30} INACTIVE_SLOTS=${VK_INACTIVE_SLOTS:-$((GAMMA * NY * 32))} OUTLET_MODE=${VK_OUTLET_MODE:-equilibrium_flux} THERMOSTAT_ENABLE=${VK_THERMOSTAT_ENABLE}" "$VK_SURVEY_EVERY"
fi

python3 - "$OUT_CSV" <<'PY'
import csv, sys
p=sys.argv[1]
with open(p, newline='') as fh:
    rows=list(csv.DictReader(fh))
active=[r for r in rows if r.get('verdict')]
failed=[r for r in active if r.get('verdict') != 'PASS']
on_rows=sum(int(r.get('surveyOnRows') or 0) for r in active)
off_rows=sum(int(r.get('surveyOffRows') or 0) for r in active)
print(f"[0295-survey] manifest={p}")
print(f"[0295-survey] cases={len(active)} failed={len(failed)} surveyRowsOff={off_rows} surveyRowsOn={on_rows} verdict={'PASS' if active and not failed and off_rows == 0 and on_rows > 0 else 'FAIL'}")
if failed:
    for r in failed:
        print(f"[0295-survey] failed-case={r.get('caseName')} offRc={r.get('offExitCode')} onRc={r.get('onExitCode')} compare={r.get('compareCsv')}")
if failed or not active or off_rows != 0 or on_rows <= 0:
    raise SystemExit(1)
PY

echo "[0295-survey] wrote $OUT_CSV"
