#!/usr/bin/env bash
set -euo pipefail

# 0198a Q6 tolerance sweep harness.
# Measures the marginal runtime/iteration cost of tightening projectionTolerance.
# This is intentionally a script-only measurement patch: no source changes.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ROOT_RUN="${ROOT_RUN:-runs/profile_q6_tolerance_sweep_0198a}"
CXX="${CXX:-g++}"
BUILD_PROFILE="${BUILD_PROFILE:-lto-native}"
NX="${NX:-96}"
NY="${NY:-96}"
GAMMA="${GAMMA:-12}"
STEPS_PROFILE="${STEPS_PROFILE:-300}"
SUMMARY_EVERY_PROFILE="${SUMMARY_EVERY_PROFILE:-${STEPS_PROFILE}}"
THREADS_LIST="${THREADS_LIST:-8}"
TIMING_EVERY="${TIMING_EVERY:-1}"
Q6_TIMING_EVERY="${Q6_TIMING_EVERY:-1}"
SEED="${SEED:-1620162}"
KBT="${KBT:-0.001}"
CASES_LIST="${CASES_LIST:-tg_q6 tg_q6_resampling}"
TOLERANCES="${TOLERANCES:-1e-6 1e-7 1e-8 1e-9 1e-10}"

export OMP_DYNAMIC="${OMP_DYNAMIC:-false}"
export OMP_PROC_BIND="${OMP_PROC_BIND:-close}"
export OMP_PLACES="${OMP_PLACES:-cores}"

mkdir -p build "$ROOT_RUN/logs" "$ROOT_RUN/params"

common_flags="-std=c++17 -Wall -Wextra -fopenmp"
case "$BUILD_PROFILE" in
  safe) opt_flags="-O2 -g -fno-omit-frame-pointer" ;;
  release) opt_flags="-O3 -DNDEBUG -g -fno-omit-frame-pointer" ;;
  native) opt_flags="-O3 -DNDEBUG -g -fno-omit-frame-pointer -march=native -mtune=native" ;;
  lto-native) opt_flags="-O3 -DNDEBUG -g -fno-omit-frame-pointer -march=native -mtune=native -flto" ;;
  *) echo "Unknown BUILD_PROFILE='$BUILD_PROFILE'. Expected: safe, release, native, lto-native" >&2; exit 2 ;;
esac

sources=(
  src/main_src_mpcd_base.cpp
  src/params_io_base.cpp
  src/cell_grid.cpp
  src/boundary_base.cpp
  src/fluid_domain.cpp
  src/immersed_solid.cpp
  src/src_collision.cpp
  src/thermostat.cpp
  src/elliptic_projection.cpp
  src/q6_projection_adapter.cpp
  src/closed_capacity_response.cpp
  src/src_mpcd_base.cpp
  src/runtime_summary.cpp
  src/particle_state.cpp
  src/state_smpcd_io.cpp
  src/weighted_resampling.cpp
)

BIN="build/src_mpcd_base_q6_tol_sweep_0198a"
echo "[0198a-build] $BIN"
"$CXX" $common_flags $opt_flags -Iinclude "${sources[@]}" -o "$BIN"

BOOT="$ROOT_RUN/bootstrap"
rm -rf "$BOOT"
AUTO_BUILD=0 \
BIN="$BIN" \
RUN_ROOT="$BOOT" \
NX="$NX" NY="$NY" GAMMA="$GAMMA" \
SEED="$SEED" KBT="$KBT" \
STEPS=1 SUMMARY_EVERY=1 DUMP_STATE_EVERY=0 \
THREADS=1 LIVE_PROGRESS=0 \
bash scripts/run_example_taylor_green.sh > "$ROOT_RUN/logs/bootstrap.stdout" 2> "$ROOT_RUN/logs/bootstrap.stderr"

TEMPLATE="$BOOT/params/taylor_green.kv"
STATE_FILE="$BOOT/init/taylor_green_${NX}x${NY}_g${GAMMA}_seed${SEED}.smpcd"
if [[ ! -f "$TEMPLATE" || ! -f "$STATE_FILE" ]]; then
  echo "ERROR: bootstrap did not create expected template/state" >&2
  echo "TEMPLATE=$TEMPLATE" >&2
  echo "STATE_FILE=$STATE_FILE" >&2
  exit 2
fi

make_variant() {
  local name="$1"
  local projection="$2"
  local resampling="$3"
  local f="$ROOT_RUN/params/${name}.kv"
  cp "$TEMPLATE" "$f"
  sed -i "s|^inputState = .*|inputState = ${STATE_FILE}|" "$f"
  sed -i "s|^outputDir = .*|outputDir = ${ROOT_RUN}/${name}/output|" "$f"
  sed -i "s|^nSteps = .*|nSteps = ${STEPS_PROFILE}|" "$f"
  sed -i "s|^summaryEvery = .*|summaryEvery = ${SUMMARY_EVERY_PROFILE}|" "$f"
  sed -i "s|^dumpStateEvery = .*|dumpStateEvery = 0|" "$f"
  sed -i "s|^projectionEnable = .*|projectionEnable = ${projection}|" "$f"
  sed -i "s|^resamplingEnable = .*|resamplingEnable = ${resampling}|" "$f"
}

make_variant tg_classic false false
make_variant tg_q6 true false
make_variant tg_q6_resampling true true

GLOBAL_CSV="$ROOT_RUN/logs/timings_q6_tolerance_sweep_0198a.csv"
echo "tolerance,case,threads,elapsed,user,sys,maxrss_kb,phase_csv,q6_csv,stdout" > "$GLOBAL_CSV"

safe_tol_label() {
  echo "$1" | sed 's/+//g; s/-/m/g; s/\./p/g'
}

run_one() {
  local tol="$1"
  local case_name="$2"
  local threads="$3"
  local label
  label="$(safe_tol_label "$tol")"
  local base_param="$ROOT_RUN/params/${case_name}.kv"
  local run_param="$ROOT_RUN/params/tol_${label}_${case_name}_t${threads}.kv"
  local out_dir="$ROOT_RUN/tol_${label}_${case_name}_t${threads}/output"
  local phase_csv="$ROOT_RUN/logs/phase_tol_${label}_${case_name}_t${threads}.csv"
  local q6_csv="$ROOT_RUN/logs/q6_tol_${label}_${case_name}_t${threads}.csv"
  local stdout="$ROOT_RUN/logs/tol_${label}_${case_name}_t${threads}.stdout"
  cp "$base_param" "$run_param"
  sed -i "s|^numThreads = .*|numThreads = ${threads}|" "$run_param"
  sed -i "s|^outputDir = .*|outputDir = ${out_dir}|" "$run_param"
  sed -i "s|^projectionTolerance = .*|projectionTolerance = ${tol}|" "$run_param"
  export OMP_NUM_THREADS="$threads"
  export MPCD_TIMING_CSV="$phase_csv"
  export MPCD_TIMING_EVERY="$TIMING_EVERY"
  export MPCD_Q6_TIMING_CSV="$q6_csv"
  export MPCD_Q6_TIMING_EVERY="$Q6_TIMING_EVERY"
  echo "[0198a-run] tol=$tol case=$case_name threads=$threads phase=$phase_csv q6=$q6_csv"
  /usr/bin/time -f "__TIME_ROW__,${tol},${case_name},${threads},%e,%U,%S,%M,${phase_csv},${q6_csv},${stdout}" \
    "$BIN" "$run_param" \
    > "$stdout" \
    2> "$ROOT_RUN/logs/tol_${label}_${case_name}_t${threads}.time"
  grep '^__TIME_ROW__,' "$ROOT_RUN/logs/tol_${label}_${case_name}_t${threads}.time" | sed 's/^__TIME_ROW__,//' >> "$GLOBAL_CSV"
}

for tol in $TOLERANCES; do
  for case_name in $CASES_LIST; do
    for threads in $THREADS_LIST; do
      run_one "$tol" "$case_name" "$threads"
    done
  done
done

python3 - "$GLOBAL_CSV" <<'PY'
import csv, re, sys
from pathlib import Path

def sum_numeric_csv(path, skip):
    rows=list(csv.DictReader(open(path, newline='')))
    out={}
    if not rows:
        return 0,out
    for k in rows[0].keys():
        if k in skip:
            continue
        vals=[]
        ok=True
        for r in rows:
            try:
                vals.append(float(r[k]))
            except Exception:
                ok=False
                break
        if ok:
            out[k]=sum(vals)
            out[k+'_mean']=sum(vals)/len(vals)
            out[k+'_min']=min(vals)
            out[k+'_max']=max(vals)
    return len(rows),out

def parse_last_summary(stdout):
    txt=Path(stdout).read_text(errors='replace')
    lines=[ln for ln in txt.splitlines() if '[src_mpcd_base]' in ln]
    last=lines[-1] if lines else ''
    out={}
    for key in ['kBT','stdN','resM','q6']:
        m=re.search(rf'{key}=([0-9.eE+-]+)', last)
        if m:
            out[key]=float(m.group(1))
    return out,last

print('\n[0198a-summary]')
records=[]
for r in csv.DictReader(open(sys.argv[1], newline='')):
    q6_n,q6=sum_numeric_csv(Path(r['q6_csv']), skip={'call'})
    phase_n,phase=sum_numeric_csv(Path(r['phase_csv']), skip={'step'})
    phys,last=parse_last_summary(r['stdout'])
    wall=float(r['elapsed'])
    rec={
        'tol':r['tolerance'], 'case':r['case'], 'threads':r['threads'], 'wall':wall,
        'q6_total':q6.get('total',0.0), 'q6_phase':phase.get('q6',0.0),
        'solve_total':q6.get('solve_total',0.0),
        'it_mean':q6.get('iterations_mean',0.0),
        'it_min':q6.get('iterations_min',0.0),
        'it_max':q6.get('iterations_max',0.0),
        'res_mean':q6.get('residual_rel_mean',0.0),
        'res_max':q6.get('residual_rel_max',0.0),
        **phys,
    }
    records.append(rec)
    print(f"case={rec['case']} tol={rec['tol']} threads={rec['threads']} wall={wall:.6g}s phase_q6={rec['q6_phase']:.6g}s q6_internal={rec['q6_total']:.6g}s solve={rec['solve_total']:.6g}s it_mean={rec['it_mean']:.3f} res_mean={rec['res_mean']:.3e} res_max={rec['res_max']:.3e} kBT={rec.get('kBT',float('nan')):.6g} stdN={rec.get('stdN',float('nan')):.6g} resM={rec.get('resM',float('nan')):.6g} q6diag={rec.get('q6',float('nan')):.3e}")

print('\n[0198a-summary] relative to tightest tolerance per case/thread')
by={}
for r in records:
    by.setdefault((r['case'],r['threads']),[]).append(r)
for key,rows in sorted(by.items()):
    rows_sorted=sorted(rows, key=lambda x: float(x['tol']))
    tight=rows_sorted[0]
    print(f"\ncase={key[0]} threads={key[1]} reference_tol={tight['tol']} wall={tight['wall']:.6g}s it={tight['it_mean']:.3f}")
    for r in sorted(rows, key=lambda x: float(x['tol']), reverse=True):
        print(f"  tol={r['tol']:<7s} wall_speedup={tight['wall']/r['wall'] if r['wall'] else 0:.4g} q6_speedup={tight['q6_total']/r['q6_total'] if r['q6_total'] else 0:.4g} iterations={r['it_mean']:.3f} residual={r['res_mean']:.3e} q6diag={r.get('q6',float('nan')):.3e}")
print(f"\n[0198a-summary] global CSV: {sys.argv[1]}")
PY
