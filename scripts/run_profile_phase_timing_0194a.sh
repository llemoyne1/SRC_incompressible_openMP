#!/usr/bin/env bash
set -euo pipefail

# 0194a phase-timing harness.
# Uses the instrumented run_src_mpcd_base_step() path controlled by:
#   MPCD_TIMING_CSV=<output csv>
#   MPCD_TIMING_EVERY=<step cadence, default 1>
# The instrumentation is inactive when MPCD_TIMING_CSV is unset.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ROOT_RUN="${ROOT_RUN:-runs/profile_phase_timing_0194a}"
CXX="${CXX:-g++}"
BUILD_PROFILE="${BUILD_PROFILE:-lto-native}"
NX="${NX:-96}"
NY="${NY:-96}"
GAMMA="${GAMMA:-12}"
STEPS_PROFILE="${STEPS_PROFILE:-300}"
SUMMARY_EVERY_PROFILE="${SUMMARY_EVERY_PROFILE:-${STEPS_PROFILE}}"
THREADS_LIST="${THREADS_LIST:-8}"
TIMING_EVERY="${TIMING_EVERY:-1}"
SEED="${SEED:-1620162}"
KBT="${KBT:-0.001}"

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

BIN="build/src_mpcd_base_profile_phase_timing_0194a"
echo "[0194a-build] $BIN"
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

GLOBAL_CSV="$ROOT_RUN/logs/timings_phase_timing_0194a.csv"
echo "case,threads,elapsed,user,sys,maxrss_kb,timing_csv" > "$GLOBAL_CSV"

run_one() {
  local case_name="$1"
  local threads="$2"
  local base_param="$ROOT_RUN/params/${case_name}.kv"
  local run_param="$ROOT_RUN/params/${case_name}_t${threads}.kv"
  local out_dir="$ROOT_RUN/${case_name}_t${threads}/output"
  local timing_csv="$ROOT_RUN/logs/phase_${case_name}_t${threads}.csv"
  cp "$base_param" "$run_param"
  sed -i "s|^numThreads = .*|numThreads = ${threads}|" "$run_param"
  sed -i "s|^outputDir = .*|outputDir = ${out_dir}|" "$run_param"
  export OMP_NUM_THREADS="$threads"
  export MPCD_TIMING_CSV="$timing_csv"
  export MPCD_TIMING_EVERY="$TIMING_EVERY"
  echo "[0194a-run] case=$case_name threads=$threads timing=$timing_csv"
  /usr/bin/time -f "__TIME_ROW__,${case_name},${threads},%e,%U,%S,%M,${timing_csv}" \
    "$BIN" "$run_param" \
    > "$ROOT_RUN/logs/${case_name}_t${threads}.stdout" \
    2> "$ROOT_RUN/logs/${case_name}_t${threads}.time"
  grep '^__TIME_ROW__,' "$ROOT_RUN/logs/${case_name}_t${threads}.time" | sed 's/^__TIME_ROW__,//' >> "$GLOBAL_CSV"
}

for case_name in tg_classic tg_q6 tg_q6_resampling; do
  for threads in $THREADS_LIST; do
    run_one "$case_name" "$threads"
  done
done

python3 - "$GLOBAL_CSV" <<'PY'
import csv, sys
from pathlib import Path

def summarize(path):
    rows=list(csv.DictReader(open(path, newline='')))
    cols=[c for c in rows[0].keys() if c != 'step'] if rows else []
    sums={c:0.0 for c in cols}
    for r in rows:
        for c in cols:
            sums[c]+=float(r[c])
    total=sums.get('total',0.0)
    ranked=sorted(((c,v) for c,v in sums.items() if c not in ('total','unaccounted') and v>0.0), key=lambda kv: kv[1], reverse=True)
    return len(rows), total, ranked, sums.get('unaccounted',0.0)

global_csv=Path(sys.argv[1])
print('\n[0194a-summary] phase totals')
for r in csv.DictReader(open(global_csv, newline='')):
    p=Path(r['timing_csv'])
    if not p.exists():
        print(f"missing phase csv: {p}")
        continue
    n,total,ranked,unacc=summarize(p)
    print(f"\ncase={r['case']} threads={r['threads']} sampled_steps={n} phase_total={total:.6g}s wall={float(r['elapsed']):.6g}s")
    for c,v in ranked[:12]:
        pct=100.0*v/total if total>0 else 0.0
        print(f"  {c:28s} {v:.6g}s {pct:6.2f}%")
    if abs(unacc) > 1e-9:
        pct=100.0*unacc/total if total>0 else 0.0
        print(f"  {'unaccounted':28s} {unacc:.6g}s {pct:6.2f}%")
print(f"\n[0194a-summary] global CSV: {global_csv}")
PY
