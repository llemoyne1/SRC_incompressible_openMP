#!/usr/bin/env bash
set -euo pipefail

# 0190a measurement-only harness.
# Compares two binaries built from the same sources:
#   checks_on  : legacy expensive particle role validation enabled
#   checks_off : production/profile validation policy; O(1) ParticleState checks only
# No physical operator is changed by this script.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ROOT_RUN="${ROOT_RUN:-runs/profile_particle_checks_0190a}"
CXX="${CXX:-g++}"
BUILD_PROFILE="${BUILD_PROFILE:-native}"
NX="${NX:-96}"
NY="${NY:-96}"
GAMMA="${GAMMA:-12}"
STEPS_PROFILE="${STEPS_PROFILE:-300}"
SUMMARY_EVERY_PROFILE="${SUMMARY_EVERY_PROFILE:-${STEPS_PROFILE}}"
THREADS_LIST="${THREADS_LIST:-1 2 4 8}"
LIVE_PROGRESS="${LIVE_PROGRESS:-0}"
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

build_solver() {
  local bin="$1"
  local extra="$2"
  echo "[0190a-build] $bin"
  echo "[0190a-build] extra='$extra'"
  "$CXX" $common_flags $opt_flags $extra -Iinclude "${sources[@]}" -o "$bin"
}

BIN_ON="build/src_mpcd_base_profile_checks_on_0190a"
BIN_OFF="build/src_mpcd_base_profile_checks_off_0190a"

build_solver "$BIN_ON" "-DMPCD_ENABLE_EXPENSIVE_PARTICLE_CHECKS"
build_solver "$BIN_OFF" ""

BOOT="$ROOT_RUN/bootstrap"
rm -rf "$BOOT"
AUTO_BUILD=0 \
BIN="$BIN_OFF" \
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

CSV="$ROOT_RUN/logs/timings_particle_checks_0190a.csv"
echo "variant,case,threads,elapsed,user,sys,maxrss_kb" > "$CSV"

run_one() {
  local variant="$1"
  local bin="$2"
  local case_name="$3"
  local threads="$4"
  local base_param="$ROOT_RUN/params/${case_name}.kv"
  local run_param="$ROOT_RUN/params/${variant}_${case_name}_t${threads}.kv"
  local out_dir="$ROOT_RUN/${variant}_${case_name}_t${threads}/output"
  cp "$base_param" "$run_param"
  sed -i "s|^numThreads = .*|numThreads = ${threads}|" "$run_param"
  sed -i "s|^outputDir = .*|outputDir = ${out_dir}|" "$run_param"
  export OMP_NUM_THREADS="$threads"
  echo "[0190a-run] variant=$variant case=$case_name threads=$threads bin=$bin"
  /usr/bin/time -f "${variant},${case_name},${threads},%e,%U,%S,%M" \
    "$bin" "$run_param" \
    > "$ROOT_RUN/logs/${variant}_${case_name}_t${threads}.stdout" \
    2> "$ROOT_RUN/logs/${variant}_${case_name}_t${threads}.time"
  cat "$ROOT_RUN/logs/${variant}_${case_name}_t${threads}.time" >> "$CSV"
}

for variant in checks_on checks_off; do
  if [[ "$variant" == "checks_on" ]]; then bin="$BIN_ON"; else bin="$BIN_OFF"; fi
  for case_name in tg_classic tg_q6 tg_q6_resampling; do
    for threads in $THREADS_LIST; do
      run_one "$variant" "$bin" "$case_name" "$threads"
    done
  done
done

python3 - "$CSV" <<'PY'
import csv, sys
from collections import defaultdict
path=sys.argv[1]
rows=list(csv.DictReader(open(path, newline='')))
print("\n[0190a-summary] elapsed seconds")
print("case,threads,checks_on,checks_off,speedup_off_vs_on")
by={}
for r in rows:
    by[(r['case'], r['threads'], r['variant'])]=float(r['elapsed'])
for case in ('tg_classic','tg_q6','tg_q6_resampling'):
    for t in sorted({r['threads'] for r in rows}, key=lambda x:int(x)):
        on=by.get((case,t,'checks_on'))
        off=by.get((case,t,'checks_off'))
        if on is not None and off is not None:
            print(f"{case},{t},{on:.6g},{off:.6g},{on/off:.6g}")
print(f"\n[0190a-summary] CSV: {path}")
PY
