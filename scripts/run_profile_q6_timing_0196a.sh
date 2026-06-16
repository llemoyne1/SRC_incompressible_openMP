#!/usr/bin/env bash
set -euo pipefail

# 0196a Q6 internal-timing harness.
# Uses the existing phase timing (MPCD_TIMING_CSV) plus Q6-internal timing:
#   MPCD_Q6_TIMING_CSV=<output csv>
#   MPCD_Q6_TIMING_EVERY=<call cadence, default 1>

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ROOT_RUN="${ROOT_RUN:-runs/profile_q6_timing_0196a}"
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

BIN="build/src_mpcd_base_profile_q6_timing_0196a"
echo "[0196a-build] $BIN"
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

GLOBAL_CSV="$ROOT_RUN/logs/timings_q6_timing_0196a.csv"
echo "case,threads,elapsed,user,sys,maxrss_kb,phase_csv,q6_csv" > "$GLOBAL_CSV"

run_one() {
  local case_name="$1"
  local threads="$2"
  local base_param="$ROOT_RUN/params/${case_name}.kv"
  local run_param="$ROOT_RUN/params/${case_name}_t${threads}.kv"
  local out_dir="$ROOT_RUN/${case_name}_t${threads}/output"
  local phase_csv="$ROOT_RUN/logs/phase_${case_name}_t${threads}.csv"
  local q6_csv="$ROOT_RUN/logs/q6_${case_name}_t${threads}.csv"
  cp "$base_param" "$run_param"
  sed -i "s|^numThreads = .*|numThreads = ${threads}|" "$run_param"
  sed -i "s|^outputDir = .*|outputDir = ${out_dir}|" "$run_param"
  export OMP_NUM_THREADS="$threads"
  export MPCD_TIMING_CSV="$phase_csv"
  export MPCD_TIMING_EVERY="$TIMING_EVERY"
  export MPCD_Q6_TIMING_CSV="$q6_csv"
  export MPCD_Q6_TIMING_EVERY="$Q6_TIMING_EVERY"
  echo "[0196a-run] case=$case_name threads=$threads phase=$phase_csv q6=$q6_csv"
  /usr/bin/time -f "__TIME_ROW__,${case_name},${threads},%e,%U,%S,%M,${phase_csv},${q6_csv}" \
    "$BIN" "$run_param" \
    > "$ROOT_RUN/logs/${case_name}_t${threads}.stdout" \
    2> "$ROOT_RUN/logs/${case_name}_t${threads}.time"
  grep '^__TIME_ROW__,' "$ROOT_RUN/logs/${case_name}_t${threads}.time" | sed 's/^__TIME_ROW__,//' >> "$GLOBAL_CSV"
}

for case_name in $CASES_LIST; do
  for threads in $THREADS_LIST; do
    run_one "$case_name" "$threads"
  done
done

python3 - "$GLOBAL_CSV" <<'PY'
import csv, sys
from pathlib import Path

def sum_csv(path, skip=('step','call')):
    rows=list(csv.DictReader(open(path, newline='')))
    if not rows:
        return 0, {}
    out={}
    for k in rows[0].keys():
        if k in skip:
            continue
        try:
            out[k]=sum(float(r[k]) for r in rows)
        except ValueError:
            pass
    return len(rows), out

print('\n[0196a-summary]')
for r in csv.DictReader(open(sys.argv[1], newline='')):
    phase_n, phase_sum = sum_csv(Path(r['phase_csv']), skip=('step',))
    q6_n, q6_sum = sum_csv(Path(r['q6_csv']), skip=('call',))
    phase_total=phase_sum.get('total',0.0)
    q6_total=q6_sum.get('total',0.0)
    print(f"\ncase={r['case']} threads={r['threads']} wall={float(r['elapsed']):.6g}s phase_total={phase_total:.6g}s q6_rows={q6_n} q6_total={q6_total:.6g}s")
    ranked=sorted(((k,v) for k,v in q6_sum.items() if k not in ('total','unaccounted','iterations','converged','residual_rel') and v>0), key=lambda kv: kv[1], reverse=True)
    for k,v in ranked[:14]:
        pct=100.0*v/q6_total if q6_total>0 else 0.0
        print(f"  {k:24s} {v:.6g}s {pct:6.2f}%")
    if 'iterations' in q6_sum and q6_n:
        print(f"  iterations_mean          {q6_sum['iterations']/q6_n:.6g}")
    if 'residual_rel' in q6_sum and q6_n:
        print(f"  residual_rel_mean        {q6_sum['residual_rel']/q6_n:.6g}")
print(f"\n[0196a-summary] global CSV: {sys.argv[1]}")
PY
