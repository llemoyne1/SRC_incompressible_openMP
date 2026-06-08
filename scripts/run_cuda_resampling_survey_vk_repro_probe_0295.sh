#!/usr/bin/env bash
set -euo pipefail

# 0295 — Von Karman survey reproducibility probe.
#
# Purpose:
#   Do not tune the survey.  Diagnose whether the 0295 OFF/ON comparison is a
#   valid non-mutation test by separating:
#     - run-to-run determinism without survey (off_a vs off_b),
#     - determinism with the least intrusive survey mode (csv_a vs csv_b),
#     - the incremental effect of enabling the survey request flag (off_a vs csv_a),
#     - the incremental effect of the full CUDA deposit survey (csv_a vs full_a).
#
# The critical observation from earlier debugging was that VK can fail even with
# MPCD_CUDA_RESAMPLING_SUPPORT_SURVEY_0295_MODE=csv_only.  If that persists,
# compute-sanitizer on survey kernels is the wrong first tool: either the demo is
# not reproducible run-to-run, the init states differ, or merely requesting the
# 0295 callback changes a host/control-flow path.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BIN=${BIN:-build/src_mpcd_base_cuda_0295}
ART_ROOT=${ART_ROOT:-dev_history/artifacts/gpu_cuda_resampling_survey_0295_vk_repro_probe}
NX=${NX:-64}
NY=${NY:-64}
GAMMA=${GAMMA:-20}
STEPS=${STEPS:-80}
THREADS=${THREADS:-8}
SURVEY_EVERY=${SURVEY_EVERY:-$STEPS}
SUMMARY_EVERY=${SUMMARY_EVERY:-$STEPS}
DUMP_STATE_EVERY=${DUMP_STATE_EVERY:-$STEPS}
LIVE_PROGRESS=${LIVE_PROGRESS:-0}
CLEAN_RUN_ROOT=${CLEAN_RUN_ROOT:-1}
VK_UIN=${VK_UIN:-0.30}
VK_OUTLET_MODE=${VK_OUTLET_MODE:-equilibrium_flux}
VK_INACTIVE_SLOTS=${VK_INACTIVE_SLOTS:-$((GAMMA * NY * 32))}
STRICT_SYNC=${STRICT_SYNC:-0}
CUDA_LAUNCH_BLOCKING=${CUDA_LAUNCH_BLOCKING:-0}
COMPARE_ABS_TOL=${COMPARE_ABS_TOL:-1e-10}
COMPARE_REL_TOL=${COMPARE_REL_TOL:-1e-9}
RUN_FULL=${RUN_FULL:-1}
mkdir -p "$ART_ROOT"

if [[ ! -x "$BIN" ]]; then
  echo "[0295-vkrepro] ERROR: missing binary $BIN" >&2
  echo "[0295-vkrepro] Build it first, e.g. OUT=$BIN bash scripts/build_src_mpcd_cuda_0295.sh" >&2
  exit 127
fi

MANIFEST="$ART_ROOT/vk_repro_probe_0295_manifest.csv"
COMPARE_MANIFEST="$ART_ROOT/vk_repro_probe_0295_compare_manifest.csv"
printf 'label,survey,mode,exitCode,initSha,finalDumpSha,summarySha,surveyRows,runRoot,summaryPath,finalDumpPath\n' > "$MANIFEST"
printf 'pair,summaryCompared,summaryFailed,summaryVerdict,initSame,finalDumpSame,summaryA,summaryB,compareCsv\n' > "$COMPARE_MANIFEST"

sha_file() {
  local p="$1"
  if [[ -n "$p" && -s "$p" ]]; then sha256sum "$p" | awk '{print $1}'; else printf 'NA'; fi
}

survey_count() {
  local root=$1
  python3 - "$root" <<'PY'
import glob, os, sys
rows=0
for p in glob.glob(os.path.join(sys.argv[1], '**', 'cuda_resampling_support_survey_0295.csv'), recursive=True):
    try:
        with open(p, newline='') as fh:
            rows += max(0, sum(1 for _ in fh) - 1)
    except FileNotFoundError:
        pass
print(rows)
PY
}

compare_summaries() {
  local a_summary=$1 b_summary=$2 out_csv=$3 abs_tol=$4 rel_tol=$5
  python3 - "$a_summary" "$b_summary" "$out_csv" "$abs_tol" "$rel_tol" <<'PY'
import csv, math, sys
from pathlib import Path
pa, pb, out, abs_s, rel_s = sys.argv[1:6]
abs_tol=float(abs_s); rel_tol=float(rel_s)
exclude_substr=('wall','elapsed','seconds','time_s','runtime','speedup','profile','log','path','file','dir','csv')
exclude_exact={'numThreadsUsed','threads','outputDir','dumpPath','runTag','case'}
def load_last(p):
    with open(p, newline='') as fh:
        rows=list(csv.DictReader(fh))
    if not rows:
        raise SystemExit(f'empty summary {p}')
    return rows[-1]
def excluded(k):
    kl=k.lower()
    return k in exclude_exact or any(s in kl for s in exclude_substr)
def to_float(v):
    if v is None or v=='': return None
    try: return float(v)
    except Exception: return None
def same_float(a,b):
    if math.isnan(a) and math.isnan(b): return True
    d=abs(a-b); scale=max(abs(a),abs(b),1.0)
    return d <= abs_tol + rel_tol*scale
ra=load_last(pa); rb=load_last(pb)
keys=[k for k in ra.keys() if k in rb and not excluded(k)]
rows=[]; compared=0; failed=0
for k in keys:
    va=(ra.get(k) or '').strip(); vb=(rb.get(k) or '').strip()
    fa=to_float(va); fb=to_float(vb)
    if fa is not None and fb is not None:
        ok=same_float(fa,fb); delta='' if (math.isnan(fa) or math.isnan(fb)) else repr(abs(fa-fb))
    else:
        ok=(va==vb); delta=''
    compared += 1
    if not ok: failed += 1
    rows.append({'metric':k,'a':va,'b':vb,'absDelta':delta,'status':'PASS' if ok else 'FAIL'})
Path(out).parent.mkdir(parents=True, exist_ok=True)
with open(out,'w',newline='') as fh:
    w=csv.DictWriter(fh, fieldnames=['metric','a','b','absDelta','status'])
    w.writeheader(); w.writerows(rows)
print(f'{compared},{failed},{"PASS" if compared>0 and failed==0 else "FAIL"}')
PY
}

run_one() {
  local label=$1 survey=$2 mode=$3
  local root="$ART_ROOT/$label"
  rm -rf "$root"
  mkdir -p "$root"
  echo "[0295-vkrepro] run label=$label survey=$survey mode=$mode root=$root"
  local rc=0
  set +e
  env \
    BIN="$BIN" AUTO_BUILD=0 LIVE_PROGRESS="$LIVE_PROGRESS" CLEAN_RUN_ROOT="$CLEAN_RUN_ROOT" \
    NX="$NX" NY="$NY" GAMMA="$GAMMA" STEPS="$STEPS" SUMMARY_EVERY="$SUMMARY_EVERY" DUMP_STATE_EVERY="$DUMP_STATE_EVERY" \
    THREADS="$THREADS" RUN_ROOT="$root" UIN="$VK_UIN" INACTIVE_SLOTS="$VK_INACTIVE_SLOTS" OUTLET_MODE="$VK_OUTLET_MODE" \
    CUDA_DIAG_STRICT_SYNC_0295="$STRICT_SYNC" CUDA_LAUNCH_BLOCKING="$CUDA_LAUNCH_BLOCKING" \
    MPCD_CUDA_RESAMPLING_SUPPORT_SURVEY_0295="$survey" \
    MPCD_CUDA_RESAMPLING_SUPPORT_SURVEY_0295_EVERY="$SURVEY_EVERY" \
    MPCD_CUDA_RESAMPLING_SUPPORT_SURVEY_0295_MODE="$mode" \
    bash scripts/run_demo_src_classic_cuda_von_karman_cylinder_0285.sh >"$root.stdout.log" 2>"$root.stderr.log"
  rc=$?
  set -e
  local init final summary
  init=$(find "$root/init" -maxdepth 1 -type f -name '*.smpcd' | sort | tail -n 1 || true)
  final=$(find "$root/output" -maxdepth 1 -type f -name 'state_step_*.smpcd' | sort | tail -n 1 || true)
  summary="$root/output/summary_runtime.csv"
  local initSha finalSha summarySha rows
  initSha=$(sha_file "$init")
  finalSha=$(sha_file "$final")
  summarySha=$(sha_file "$summary")
  rows=$(survey_count "$root")
  python3 - "$MANIFEST" "$label" "$survey" "$mode" "$rc" "$initSha" "$finalSha" "$summarySha" "$rows" "$root" "$summary" "$final" <<'PY'
import csv, sys
with open(sys.argv[1], 'a', newline='') as fh:
    csv.writer(fh).writerow(sys.argv[2:])
PY
}

run_one off_a 0 disabled
run_one off_b 0 disabled
run_one csv_a 1 csv_only
run_one csv_b 1 csv_only
if [[ "$RUN_FULL" != "0" ]]; then
  run_one full_a 1 full
  run_one full_b 1 full
fi

python3 - "$MANIFEST" "$COMPARE_MANIFEST" "$COMPARE_ABS_TOL" "$COMPARE_REL_TOL" <<'PY'
import csv, os, sys, subprocess
manifest, compare_manifest, abs_tol, rel_tol = sys.argv[1:5]
with open(manifest, newline='') as fh:
    rows={r['label']:r for r in csv.DictReader(fh)}
pairs=[('off_vs_off','off_a','off_b'),('csv_vs_csv','csv_a','csv_b'),('off_vs_csv','off_a','csv_a')]
if 'full_a' in rows:
    pairs += [('full_vs_full','full_a','full_b'),('csv_vs_full','csv_a','full_a')]
# Use the shell script's embedded Python comparator by calling this same file is hard;
# instead do a compact comparison here.
def load_last(p):
    with open(p, newline='') as fh:
        data=list(csv.DictReader(fh))
    if not data: raise RuntimeError(f'empty summary {p}')
    return data[-1]
exclude_substr=('wall','elapsed','seconds','time_s','runtime','speedup','profile','log','path','file','dir','csv')
exclude_exact={'numThreadsUsed','threads','outputDir','dumpPath','runTag','case'}
def excluded(k): return k in exclude_exact or any(s in k.lower() for s in exclude_substr)
def as_float(v):
    if v is None or v=='': return None
    try: return float(v)
    except Exception: return None
import math
abs_tol=float(abs_tol); rel_tol=float(rel_tol)
def same_float(a,b):
    if math.isnan(a) and math.isnan(b): return True
    return abs(a-b) <= abs_tol + rel_tol*max(abs(a),abs(b),1.0)
with open(compare_manifest, 'a', newline='') as cm:
    w=csv.writer(cm)
    for pair,a,b in pairs:
        ra, rb = rows[a], rows[b]
        comp_csv=os.path.join(os.path.dirname(compare_manifest), pair + '_summary_compare.csv')
        compared=0; failed=0; details=[]
        if os.path.exists(ra['summaryPath']) and os.path.exists(rb['summaryPath']):
            sa=load_last(ra['summaryPath']); sb=load_last(rb['summaryPath'])
            for k in [k for k in sa.keys() if k in sb and not excluded(k)]:
                va=(sa.get(k) or '').strip(); vb=(sb.get(k) or '').strip()
                fa=as_float(va); fb=as_float(vb)
                if fa is not None and fb is not None:
                    ok=same_float(fa,fb); delta='' if (math.isnan(fa) or math.isnan(fb)) else repr(abs(fa-fb))
                else:
                    ok=(va==vb); delta=''
                compared += 1
                if not ok: failed += 1
                details.append({'metric':k,'a':va,'b':vb,'absDelta':delta,'status':'PASS' if ok else 'FAIL'})
        with open(comp_csv, 'w', newline='') as fh:
            dw=csv.DictWriter(fh, fieldnames=['metric','a','b','absDelta','status'])
            dw.writeheader(); dw.writerows(details)
        initSame = (ra['initSha'] == rb['initSha'])
        finalSame = (ra['finalDumpSha'] == rb['finalDumpSha'])
        verdict='PASS' if compared>0 and failed==0 else 'FAIL'
        w.writerow([pair, compared, failed, verdict, int(initSame), int(finalSame), ra['summaryPath'], rb['summaryPath'], comp_csv])
print(f'[0295-vkrepro] wrote {manifest}')
print(f'[0295-vkrepro] wrote {compare_manifest}')
PY

cat "$COMPARE_MANIFEST"
