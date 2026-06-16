#!/usr/bin/env bash
set -euo pipefail

# 0200a particle/deposit audit harness.
# Counts hot role/access/indexing calls on sampled steps to quantify redundant
# particle scans and particle->cell deposits.  Timings under audit are NOT meant
# to be used as performance timings because instrumentation adds overhead.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ROOT_RUN="${ROOT_RUN:-runs/profile_particle_audit_0200a}"
CXX="${CXX:-g++}"
BUILD_PROFILE="${BUILD_PROFILE:-lto-native}"
NX="${NX:-96}"
NY="${NY:-96}"
GAMMA="${GAMMA:-12}"
STEPS_PROFILE="${STEPS_PROFILE:-300}"
SUMMARY_EVERY_PROFILE="${SUMMARY_EVERY_PROFILE:-300}"
THREADS_LIST="${THREADS_LIST:-8}"
AUDIT_EVERY="${AUDIT_EVERY:-10}"
TIMING_EVERY="${TIMING_EVERY:-10}"
Q6_TIMING_EVERY="${Q6_TIMING_EVERY:-0}"
SEED="${SEED:-1620162}"
KBT="${KBT:-0.001}"
CASES_LIST="${CASES_LIST:-tg_classic tg_q6 tg_q6_resampling}"
PROJECTION_TOLERANCE="${PROJECTION_TOLERANCE:-1e-10}"

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

BIN="build/src_mpcd_base_particle_audit_0200a"
echo "[0200a-build] $BIN"
"$CXX" $common_flags $opt_flags -Iinclude "${sources[@]}" -o "$BIN"

BOOT="$ROOT_RUN/bootstrap"
rm -rf "$BOOT"
AUTO_BUILD=0 \
BIN="$BIN" \
RUN_ROOT="$BOOT" \
NX="$NX" NY="$NY" GAMMA="$GAMMA" \
SEED="$SEED" KBT="$KBT" PROJECTION_TOLERANCE="$PROJECTION_TOLERANCE" \
STEPS=1 SUMMARY_EVERY=1 DUMP_STATE_EVERY=0 \
THREADS=1 LIVE_PROGRESS=0 \
bash scripts/run_example_taylor_green.sh > "$ROOT_RUN/logs/bootstrap.stdout" 2> "$ROOT_RUN/logs/bootstrap.stderr"

TEMPLATE="$BOOT/params/taylor_green.kv"
STATE_FILE="$BOOT/init/taylor_green_${NX}x${NY}_g${GAMMA}_seed${SEED}.smpcd"
if [[ ! -f "$TEMPLATE" || ! -f "$STATE_FILE" ]]; then
  echo "ERROR: bootstrap did not create expected template/state" >&2
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
  sed -i "s|^projectionTolerance = .*|projectionTolerance = ${PROJECTION_TOLERANCE}|" "$f"
}

make_variant tg_classic false false
make_variant tg_q6 true false
make_variant tg_q6_resampling true true

GLOBAL_CSV="$ROOT_RUN/logs/timings_particle_audit_0200a.csv"
echo "case,threads,elapsed,user,sys,maxrss_kb,audit_csv,phase_csv,q6_csv,stdout" > "$GLOBAL_CSV"

run_one() {
  local case_name="$1"
  local threads="$2"
  local base_param="$ROOT_RUN/params/${case_name}.kv"
  local run_param="$ROOT_RUN/params/${case_name}_t${threads}.kv"
  local out_dir="$ROOT_RUN/${case_name}_t${threads}/output"
  local audit_csv="$ROOT_RUN/logs/audit_${case_name}_t${threads}.csv"
  local phase_csv="$ROOT_RUN/logs/phase_${case_name}_t${threads}.csv"
  local q6_csv="$ROOT_RUN/logs/q6_${case_name}_t${threads}.csv"
  local stdout="$ROOT_RUN/logs/${case_name}_t${threads}.stdout"
  cp "$base_param" "$run_param"
  sed -i "s|^numThreads = .*|numThreads = ${threads}|" "$run_param"
  sed -i "s|^outputDir = .*|outputDir = ${out_dir}|" "$run_param"
  rm -f "$audit_csv" "$phase_csv" "$q6_csv"
  export OMP_NUM_THREADS="$threads"
  export MPCD_PARTICLE_AUDIT_CSV="$audit_csv"
  export MPCD_PARTICLE_AUDIT_EVERY="$AUDIT_EVERY"
  export MPCD_TIMING_CSV="$phase_csv"
  export MPCD_TIMING_EVERY="$TIMING_EVERY"
  if [[ "$Q6_TIMING_EVERY" != "0" ]]; then
    export MPCD_Q6_TIMING_CSV="$q6_csv"
    export MPCD_Q6_TIMING_EVERY="$Q6_TIMING_EVERY"
  else
    unset MPCD_Q6_TIMING_CSV || true
    unset MPCD_Q6_TIMING_EVERY || true
  fi
  echo "[0200a-run] case=$case_name threads=$threads audit=$audit_csv every=$AUDIT_EVERY"
  /usr/bin/time -f "__TIME_ROW__,${case_name},${threads},%e,%U,%S,%M,${audit_csv},${phase_csv},${q6_csv},${stdout}" \
    "$BIN" "$run_param" \
    > "$stdout" \
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
import math

print('\n[0200a-summary] particle audit counts are sampled; timings include audit overhead.')
for r in csv.DictReader(open(sys.argv[1], newline='')):
    path=Path(r['audit_csv'])
    if not path.exists():
        print(f"missing audit csv: {path}")
        continue
    rows=list(csv.DictReader(open(path, newline='')))
    if not rows:
        print(f"empty audit csv: {path}")
        continue
    def s(col): return sum(float(x[col]) for x in rows)
    n=len(rows)
    npart=float(rows[0]['n_particles']) if rows else 0.0
    print(f"\ncase={r['case']} threads={r['threads']} sampled_steps={n} audit_every rows={path}")
    for col in [
        'cell_index_from_position_calls',
        'is_fluid_particle_calls',
        'particle_role_value_calls',
        'is_fluid_role_calls',
        'count_particle_roles_calls',
        'compute_cell_counts_calls',
        'set_particle_role_calls',
        'ensure_particle_roles_calls',
        'validate_particle_state_calls',
    ]:
        val=s(col)
        per_step=val/n if n else 0.0
        per_particle=per_step/npart if npart else 0.0
        print(f"  {col:36s} total={val:.0f} per_step={per_step:.2f} per_particle={per_particle:.4f}")
PY
