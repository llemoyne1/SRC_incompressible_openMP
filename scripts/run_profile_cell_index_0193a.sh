#!/usr/bin/env bash
set -euo pipefail

# 0193a measurement-only harness.
# Compares particle-to-cell indexing policies:
#   index_legacy : original per-call boundary queries + fmod/floor path
#   index_fast   : CellGrid cached periodic flags/reciprocals + fast one-wrap periodic path
# Physical operators are unchanged; only integer cell-index computation is specialized.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ROOT_RUN="${ROOT_RUN:-runs/profile_cell_index_0193a}"
CXX="${CXX:-g++}"
BUILD_PROFILE="${BUILD_PROFILE:-lto-native}"
NX="${NX:-96}"
NY="${NY:-96}"
GAMMA="${GAMMA:-12}"
STEPS_PROFILE="${STEPS_PROFILE:-300}"
SUMMARY_EVERY_PROFILE="${SUMMARY_EVERY_PROFILE:-${STEPS_PROFILE}}"
THREADS_LIST="${THREADS_LIST:-1 2 4 8}"
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
  echo "[0193a-build] $bin"
  echo "[0193a-build] extra='$extra'"
  "$CXX" $common_flags $opt_flags $extra -Iinclude "${sources[@]}" -o "$bin"
}

BIN_LEGACY="build/src_mpcd_base_profile_index_legacy_0193a"
BIN_FAST="build/src_mpcd_base_profile_index_fast_0193a"

build_solver "$BIN_LEGACY" "-DMPCD_DISABLE_FAST_CELL_INDEX"
build_solver "$BIN_FAST" ""

BOOT="$ROOT_RUN/bootstrap"
rm -rf "$BOOT"
AUTO_BUILD=0 \
BIN="$BIN_FAST" \
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

CSV="$ROOT_RUN/logs/timings_cell_index_0193a.csv"
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
  echo "[0193a-run] variant=$variant case=$case_name threads=$threads bin=$bin"
  /usr/bin/time -f "${variant},${case_name},${threads},%e,%U,%S,%M" \
    "$bin" "$run_param" \
    > "$ROOT_RUN/logs/${variant}_${case_name}_t${threads}.stdout" \
    2> "$ROOT_RUN/logs/${variant}_${case_name}_t${threads}.time"
  cat "$ROOT_RUN/logs/${variant}_${case_name}_t${threads}.time" >> "$CSV"
}

for variant in index_legacy index_fast; do
  if [[ "$variant" == "index_legacy" ]]; then bin="$BIN_LEGACY"; else bin="$BIN_FAST"; fi
  for case_name in tg_classic tg_q6 tg_q6_resampling; do
    for threads in $THREADS_LIST; do
      run_one "$variant" "$bin" "$case_name" "$threads"
    done
  done
done

python3 - "$CSV" <<'PY'
import csv, sys
path=sys.argv[1]
rows=list(csv.DictReader(open(path, newline='')))
print("\n[0193a-summary] elapsed seconds")
print("case,threads,index_legacy,index_fast,speedup_fast_vs_legacy")
by={(r['case'], r['threads'], r['variant']): float(r['elapsed']) for r in rows}
for case in ('tg_classic','tg_q6','tg_q6_resampling'):
    for t in sorted({r['threads'] for r in rows}, key=lambda x:int(x)):
        legacy=by.get((case,t,'index_legacy'))
        fast=by.get((case,t,'index_fast'))
        if legacy is not None and fast is not None:
            print(f"{case},{t},{legacy:.6g},{fast:.6g},{legacy/fast:.6g}")
print(f"\n[0193a-summary] CSV: {path}")
PY
