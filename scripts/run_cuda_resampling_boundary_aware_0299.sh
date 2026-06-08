#!/usr/bin/env bash
set -euo pipefail

# 0299 — boundary-aware post-SRC CUDA population guard validation.
#
# Default validation is intentionally non-triggering: the guard, 0298 restoration path, and 0299 boundary filtering are called and
# write diagnostics, but NMIN=0 and NMAX=0 disable split/merge.  This gives the
# same strict OFF/ON non-perturbation check used by 0295/0296/0297/0298. Active mutation
# experiments are enabled explicitly by setting GUARD_NMIN/GUARD_NMAX.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BIN=${BIN:-build/src_mpcd_base_cuda_0299}
ART_DIR=${ART_DIR:-dev_history/artifacts/gpu_cuda_resampling_boundary_aware_0299}
NX=${NX:-64}
NY=${NY:-64}
GAMMA=${GAMMA:-20}
STEPS=${STEPS:-80}
THREADS=${THREADS:-8}
GUARD_EVERY=${GUARD_EVERY:-10}
GUARD_NMIN=${GUARD_NMIN:-0}
GUARD_NTARGET=${GUARD_NTARGET:-20}
GUARD_NMAX=${GUARD_NMAX:-0}
GUARD_SPLIT_FRACTION=${GUARD_SPLIT_FRACTION:-0.5}
RESTORE_ENABLE=${RESTORE_ENABLE:-1}
RESTORE_MAX_SCALE=${RESTORE_MAX_SCALE:-4.0}
RESTORE_MIN_CURRENT_KREL=${RESTORE_MIN_CURRENT_KREL:-1e-30}
RESTORE_ABS_TOL=${RESTORE_ABS_TOL:-1e-14}
RESTORE_REL_TOL=${RESTORE_REL_TOL:-1e-12}
BOUNDARY_AWARE=${BOUNDARY_AWARE:-1}
BOUNDARY_HALO_CELLS=${BOUNDARY_HALO_CELLS:-0}
OPEN_BOUNDARY_HALO_CELLS=${OPEN_BOUNDARY_HALO_CELLS:-1}
SOLID_HALO_CELLS=${SOLID_HALO_CELLS:-0}
VK_GUARD_EVERY=${VK_GUARD_EVERY:-$STEPS}
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

SUMMARY_EVERY=${SUMMARY_EVERY:-$STEPS}
DUMP_STATE_EVERY=${DUMP_STATE_EVERY:-$STEPS}
LIVE_PROGRESS=${LIVE_PROGRESS:-0}
CLEAN_RUN_ROOT=${CLEAN_RUN_ROOT:-1}
AUTO_BUILD=${AUTO_BUILD:-0}

mkdir -p "$ART_DIR"

if [[ "$FORCE_REBUILD" != "0" && "$FORCE_REBUILD" != "false" && "$FORCE_REBUILD" != "FALSE" ]]; then
  echo "[0299-boundary] rebuilding $BIN"
  OUT="$BIN" CUDA_ARCH_FLAGS="${CUDA_ARCH_FLAGS:-}" bash scripts/build_src_mpcd_cuda_0299.sh
elif [[ ! -x "$BIN" ]]; then
  OUT="$BIN" CUDA_ARCH_FLAGS="${CUDA_ARCH_FLAGS:-}" bash scripts/build_src_mpcd_cuda_0299.sh
fi
if [[ ! -x "$BIN" ]]; then
  echo "[0299-boundary] ERROR: missing binary $BIN" >&2
  exit 127
fi

OUT_CSV=${OUT_CSV:-$ART_DIR/cuda_resampling_boundary_aware_0299_manifest.csv}
printf 'caseName,guardOffRoot,guardOnRoot,offExitCode,onExitCode,comparedMetrics,failedMetrics,verdict,guardOffFiles,guardOffRows,guardOnFiles,guardOnRows,guardOnSplitApplied,guardOnMergeApplied,guardOnPoorCells,guardOnRichCells,guardOnExcludedBoundary0299,guardOnExcludedOpen0299,guardOnExcludedSolid0299,compareCsv\n' > "$OUT_CSV"

append_row() {
  python3 - "$OUT_CSV" "$@" <<'PY'
import csv, sys
out=sys.argv[1]
with open(out, 'a', newline='') as fh:
    csv.writer(fh).writerow(sys.argv[2:])
PY
}

guard_count() {
  local root=$1
  python3 - "$root" <<'PY'
import csv, glob, os, sys
files=glob.glob(os.path.join(sys.argv[1], '**', 'cuda_resampling_population_guard_0297.csv'), recursive=True)
rows=0; split=0; merge=0; poor=0; rich=0; exclB=0; exclO=0; exclS=0
for p in files:
    try:
        with open(p, newline='') as fh:
            for r in csv.DictReader(fh):
                rows += 1
                split += int(float(r.get('splitApplied') or 0))
                merge += int(float(r.get('mergeApplied') or 0))
                poor += int(float(r.get('poorCells') or 0))
                rich += int(float(r.get('richCells') or 0))
                exclB += int(float(r.get('excludedBoundaryCells0299') or 0))
                exclO += int(float(r.get('excludedOpenBoundaryCells0299') or 0))
                exclS += int(float(r.get('excludedSolidHaloCells0299') or 0))
    except FileNotFoundError:
        pass
print(f"{len(files)},{rows},{split},{merge},{poor},{rich},{exclB},{exclO},{exclS}")
PY
}

compare_summaries() {
  local off_summary=$1 on_summary=$2 out_csv=$3 abs_tol=$4 rel_tol=$5
  python3 - "$off_summary" "$on_summary" "$out_csv" "$abs_tol" "$rel_tol" <<'PY'
import csv, math, sys
from pathlib import Path

off_path, on_path, out_path, abs_tol_s, rel_tol_s = sys.argv[1:6]
abs_tol=float(abs_tol_s); rel_tol=float(rel_tol_s)
EXCLUDE_EXACT = {'wallTime','wallTime_s','elapsed_s','elapsedSeconds','totalSeconds','uploadSeconds','kernelSeconds','downloadSeconds','phaseSeconds','numThreadsUsed','threads','outputDir','dumpPath','runTag','case'}
EXCLUDE_SUBSTR = ('wall','elapsed','seconds','time_s','runtime','speedup','profile','log','path','file','dir','csv')

def load_last(path):
    with open(path, newline='') as fh:
        rows=list(csv.DictReader(fh))
    if not rows:
        raise SystemExit(f'empty summary: {path}')
    return rows[-1]

def excluded(k):
    kl=k.strip().lower()
    if k in EXCLUDE_EXACT or kl in {x.lower() for x in EXCLUDE_EXACT}:
        return True
    return any(s in kl for s in EXCLUDE_SUBSTR)

def as_float(v):
    if v is None or v == '': return None
    try: return float(v)
    except Exception: return None

def same(a,b):
    if math.isnan(a) and math.isnan(b): return True
    if math.isinf(a) or math.isinf(b): return a == b
    return abs(a-b) <= abs_tol + rel_tol*max(abs(a),abs(b),1.0)

ro=load_last(off_path); rn=load_last(on_path)
rows=[]; compared=0; failed=0
for k in [k for k in ro.keys() if k in rn and not excluded(k)]:
    vo=(ro.get(k) or '').strip(); vn=(rn.get(k) or '').strip()
    fo=as_float(vo); fn=as_float(vn)
    if fo is not None and fn is not None:
        ok=same(fo,fn); compared += 1; failed += 0 if ok else 1
        rows.append({'metric':k,'off':vo,'on':vn,'absDelta':repr(abs(fo-fn)), 'status':'PASS' if ok else 'FAIL'})
    elif vo or vn:
        ok=(vo == vn); compared += 1; failed += 0 if ok else 1
        rows.append({'metric':k,'off':vo,'on':vn,'absDelta':'', 'status':'PASS' if ok else 'FAIL'})
Path(out_path).parent.mkdir(parents=True, exist_ok=True)
with open(out_path, 'w', newline='') as fh:
    w=csv.DictWriter(fh, fieldnames=['metric','off','on','absDelta','status'])
    w.writeheader(); w.writerows(rows)
print(f'{compared},{failed},{"PASS" if compared > 0 and failed == 0 else "FAIL"}')
PY
}

run_demo_pair() {
  local case_name=$1 script=$2 nx=$3 ny=$4 steps=$5 extra_env=${6:-} guard_every=${7:-$GUARD_EVERY}
  local case_art="$ART_DIR/$case_name"
  local off_root="$case_art/guard_off"
  local on_root="$case_art/guard_on"
  mkdir -p "$case_art"

  echo "[0299-boundary] running case=$case_name guard=0 every=$guard_every script=$script"
  local off_rc=0
  set +e
  env BIN="$BIN" AUTO_BUILD=0 LIVE_PROGRESS="$LIVE_PROGRESS" CLEAN_RUN_ROOT="$CLEAN_RUN_ROOT" \
      NX="$nx" NY="$ny" GAMMA="$GAMMA" STEPS="$steps" SUMMARY_EVERY="$steps" DUMP_STATE_EVERY="$steps" \
      THREADS="$THREADS" RUN_ROOT="$off_root" \
      MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297=0 \
      MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_EVERY="$guard_every" \
      MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_NMIN="$GUARD_NMIN" \
      MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_NTARGET="$GUARD_NTARGET" \
      MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_NMAX="$GUARD_NMAX" \
      MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_SPLIT_FRACTION="$GUARD_SPLIT_FRACTION" \
      MPCD_CUDA_RESAMPLING_MOMENT_RESTORE_0298="$RESTORE_ENABLE" \
      MPCD_CUDA_RESAMPLING_MOMENT_RESTORE_0298_MAX_SCALE="$RESTORE_MAX_SCALE" \
      MPCD_CUDA_RESAMPLING_MOMENT_RESTORE_0298_MIN_CURRENT_KREL="$RESTORE_MIN_CURRENT_KREL" \
      MPCD_CUDA_RESAMPLING_MOMENT_RESTORE_0298_ABS_TOL="$RESTORE_ABS_TOL" \
      MPCD_CUDA_RESAMPLING_MOMENT_RESTORE_0298_REL_TOL="$RESTORE_REL_TOL" \
      MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0299_BOUNDARY_AWARE="$BOUNDARY_AWARE" \
      MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0299_BOUNDARY_HALO_CELLS="$BOUNDARY_HALO_CELLS" \
      MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0299_OPEN_BOUNDARY_HALO_CELLS="$OPEN_BOUNDARY_HALO_CELLS" \
      MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0299_SOLID_HALO_CELLS="$SOLID_HALO_CELLS" \
      $extra_env bash "$script" >"$case_art/guard_off.stdout.log" 2>"$case_art/guard_off.stderr.log"
  off_rc=$?
  set -e

  echo "[0299-boundary] running case=$case_name guard=1 every=$guard_every script=$script"
  local on_rc=0
  set +e
  env BIN="$BIN" AUTO_BUILD=0 LIVE_PROGRESS="$LIVE_PROGRESS" CLEAN_RUN_ROOT="$CLEAN_RUN_ROOT" \
      NX="$nx" NY="$ny" GAMMA="$GAMMA" STEPS="$steps" SUMMARY_EVERY="$steps" DUMP_STATE_EVERY="$steps" \
      THREADS="$THREADS" RUN_ROOT="$on_root" \
      MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297=1 \
      MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_EVERY="$guard_every" \
      MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_NMIN="$GUARD_NMIN" \
      MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_NTARGET="$GUARD_NTARGET" \
      MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_NMAX="$GUARD_NMAX" \
      MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_SPLIT_FRACTION="$GUARD_SPLIT_FRACTION" \
      MPCD_CUDA_RESAMPLING_MOMENT_RESTORE_0298="$RESTORE_ENABLE" \
      MPCD_CUDA_RESAMPLING_MOMENT_RESTORE_0298_MAX_SCALE="$RESTORE_MAX_SCALE" \
      MPCD_CUDA_RESAMPLING_MOMENT_RESTORE_0298_MIN_CURRENT_KREL="$RESTORE_MIN_CURRENT_KREL" \
      MPCD_CUDA_RESAMPLING_MOMENT_RESTORE_0298_ABS_TOL="$RESTORE_ABS_TOL" \
      MPCD_CUDA_RESAMPLING_MOMENT_RESTORE_0298_REL_TOL="$RESTORE_REL_TOL" \
      MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0299_BOUNDARY_AWARE="$BOUNDARY_AWARE" \
      MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0299_BOUNDARY_HALO_CELLS="$BOUNDARY_HALO_CELLS" \
      MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0299_OPEN_BOUNDARY_HALO_CELLS="$OPEN_BOUNDARY_HALO_CELLS" \
      MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0299_SOLID_HALO_CELLS="$SOLID_HALO_CELLS" \
      $extra_env bash "$script" >"$case_art/guard_on.stdout.log" 2>"$case_art/guard_on.stderr.log"
  on_rc=$?
  set -e

  local off_files off_rows off_split off_merge off_poor off_rich on_files on_rows on_split on_merge on_poor on_rich
  IFS=, read -r off_files off_rows off_split off_merge off_poor off_rich off_exclB off_exclO off_exclS <<<"$(guard_count "$off_root")"
  IFS=, read -r on_files on_rows on_split on_merge on_poor on_rich on_exclB on_exclO on_exclS <<<"$(guard_count "$on_root")"

  local compared=0 failed=999999 verdict=FAIL
  local compare_csv="$case_art/${case_name}_guard_off_vs_on_compare.csv"
  if [[ "$off_rc" == "0" && "$on_rc" == "0" && -s "$off_root/output/summary_runtime.csv" && -s "$on_root/output/summary_runtime.csv" ]]; then
    IFS=, read -r compared failed verdict <<<"$(compare_summaries "$off_root/output/summary_runtime.csv" "$on_root/output/summary_runtime.csv" "$compare_csv" "$COMPARE_ABS_TOL" "$COMPARE_REL_TOL")"
  fi
  if [[ "$off_rc" != "0" || "$on_rc" != "0" || "$off_rows" != "0" || "$on_rows" == "0" ]]; then
    verdict=FAIL
  fi

  append_row "$case_name" "$off_root" "$on_root" "$off_rc" "$on_rc" "$compared" "$failed" "$verdict" "$off_files" "$off_rows" "$on_files" "$on_rows" "$on_split" "$on_merge" "$on_poor" "$on_rich" "$on_exclB" "$on_exclO" "$on_exclS" "$compare_csv"
  echo "[0299-boundary] case=$case_name verdict=$verdict compared=$compared failed=$failed guardRowsOff=$off_rows guardRowsOn=$on_rows splitOn=$on_split mergeOn=$on_merge poorOn=$on_poor richOn=$on_rich excludedOpen0299=$on_exclO excludedBoundary0299=$on_exclB excludedSolid0299=$on_exclS"
  if [[ "$STOP_ON_FAIL" == "1" && "$verdict" != "PASS" ]]; then
    echo "[0299-boundary] FAIL case=$case_name" >&2
    echo "[0299-boundary] stdout/stderr: $case_art/guard_off.*.log $case_art/guard_on.*.log" >&2
    exit 1
  fi
}

if [[ "$RUN_TG" != "0" ]]; then
  run_demo_pair tg_periodic scripts/run_demo_src_classic_cuda_taylor_green_forced_0283.sh "$NX" "$NY" "$STEPS" "" "$GUARD_EVERY"
fi
if [[ "$RUN_POISEUILLE" != "0" ]]; then
  run_demo_pair poiseuille_wall scripts/run_demo_src_classic_cuda_poiseuille_periodic_forced_0283.sh "$NX" "$NY" "$STEPS" "" "$GUARD_EVERY"
fi
if [[ "$RUN_STEP" != "0" ]]; then
  run_demo_pair backward_step_io scripts/run_demo_src_classic_cuda_backward_step_io_0283.sh "$NX" "$NY" "$STEPS" "" "$GUARD_EVERY"
fi
if [[ "$RUN_SEGMENTED" != "0" ]]; then
  run_demo_pair segmented_box_same_face scripts/run_demo_src_classic_cuda_box_same_face_io_0283.sh "$NX" "$NY" "$STEPS" "OUTLET_MODE=${SEGMENTED_OUTLET_MODE:-neumann}" "$GUARD_EVERY"
fi
if [[ "$RUN_VK" != "0" ]]; then
  run_demo_pair von_karman_circle_io scripts/run_demo_src_classic_cuda_von_karman_cylinder_0285.sh "$NX" "$NY" "$STEPS" "UIN=${VK_UIN:-0.30} INACTIVE_SLOTS=${VK_INACTIVE_SLOTS:-$((GAMMA * NY * 32))} OUTLET_MODE=${VK_OUTLET_MODE:-equilibrium_flux} THERMOSTAT_ENABLE=${VK_THERMOSTAT_ENABLE}" "$VK_GUARD_EVERY"
fi

python3 - "$OUT_CSV" <<'PY'
import csv, sys
p=sys.argv[1]
with open(p, newline='') as fh:
    rows=list(csv.DictReader(fh))
active=[r for r in rows if r.get('verdict')]
failed=[r for r in active if r.get('verdict') != 'PASS']
on_rows=sum(int(r.get('guardOnRows') or 0) for r in active)
off_rows=sum(int(r.get('guardOffRows') or 0) for r in active)
on_split=sum(int(r.get('guardOnSplitApplied') or 0) for r in active)
on_merge=sum(int(r.get('guardOnMergeApplied') or 0) for r in active)
print(f"[0299-boundary] manifest={p}")
print(f"[0299-boundary] cases={len(active)} failed={len(failed)} guardRowsOff={off_rows} guardRowsOn={on_rows} splitOn={on_split} mergeOn={on_merge} verdict={'PASS' if active and not failed and off_rows == 0 and on_rows > 0 else 'FAIL'}")
if failed:
    for r in failed:
        print(f"[0299-boundary] failed-case={r.get('caseName')} offRc={r.get('offExitCode')} onRc={r.get('onExitCode')} compare={r.get('compareCsv')}")
if failed or not active or off_rows != 0 or on_rows <= 0:
    raise SystemExit(1)
PY

echo "[0299-boundary] wrote $OUT_CSV"
