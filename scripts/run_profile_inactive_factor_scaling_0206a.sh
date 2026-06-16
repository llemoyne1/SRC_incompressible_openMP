#!/usr/bin/env bash
set -euo pipefail

# 0206b scaling of inactive slots for the optimized bulk fluidSlots path.
# Fixes 0206a path capture; this script varies INACTIVE_FACTOR while keeping the active Taylor--Green state fixed.
# It is intended to reveal remaining O(Ntotal) loops after 0202a/0204a/0205a.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ROOT_RUN="${ROOT_RUN:-runs/profile_inactive_factor_scaling_0206a}"
CXX="${CXX:-g++}"
BUILD_PROFILE="${BUILD_PROFILE:-lto-native}"
NX="${NX:-96}"
NY="${NY:-96}"
GAMMA="${GAMMA:-12}"
STEPS_PROFILE="${STEPS_PROFILE:-300}"
SUMMARY_EVERY_PROFILE="${SUMMARY_EVERY_PROFILE:-300}"
THREADS_LIST="${THREADS_LIST:-8}"
TIMING_EVERY="${TIMING_EVERY:-1}"
AUDIT_ENABLE="${AUDIT_ENABLE:-1}"
AUDIT_EVERY="${AUDIT_EVERY:-10}"
SEED="${SEED:-1620162}"
KBT="${KBT:-0.001}"
PROJECTION_TOLERANCE="${PROJECTION_TOLERANCE:-1e-10}"
CASE_NAME="${CASE_NAME:-tg_q6_resampling}"
INACTIVE_FACTORS="${INACTIVE_FACTORS:-0 0.5 1 2 3}"
MODES_LIST="${MODES_LIST:-bulk}"

export OMP_DYNAMIC="${OMP_DYNAMIC:-false}"
export OMP_PROC_BIND="${OMP_PROC_BIND:-close}"
export OMP_PLACES="${OMP_PLACES:-cores}"

mkdir -p build "$ROOT_RUN/logs" "$ROOT_RUN/params" "$ROOT_RUN/init"

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

BIN="build/src_mpcd_base_inactive_factor_scaling_0206a"
echo "[0206a-build] $BIN"
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
STATE_FILE_ACTIVE="$BOOT/init/taylor_green_${NX}x${NY}_g${GAMMA}_seed${SEED}.smpcd"
if [[ ! -f "$TEMPLATE" || ! -f "$STATE_FILE_ACTIVE" ]]; then
  echo "ERROR: bootstrap did not create expected template/state" >&2
  exit 2
fi

GLOBAL_CSV="$ROOT_RUN/logs/timings_inactive_factor_scaling_0206a.csv"
echo "inactive_factor,mode,run_kind,threads,elapsed,user,sys,maxrss_kb,phase_csv,audit_csv,stdout" > "$GLOBAL_CSV"

make_factor_tag() {
  local f="$1"
  echo "$f" | sed 's/-/m/g; s/\./p/g; s/+//g'
}

make_param_for_factor() {
  local factor="$1"
  local tag="$2"
  local state_file="$ROOT_RUN/init/taylor_green_${NX}x${NY}_g${GAMMA}_seed${SEED}_inactive_factor_${tag}.smpcd"
  local augment_log="$ROOT_RUN/logs/augment_factor_${tag}.stdout"
  python3 scripts/augment_smpcd_inactive_bulk_0205a.py \
    "$STATE_FILE_ACTIVE" "$state_file" auto "$factor" \
    > "$augment_log"
  local param="$ROOT_RUN/params/${CASE_NAME}_factor_${tag}.kv"
  cp "$TEMPLATE" "$param"
  sed -i "s|^inputState = .*|inputState = ${state_file}|" "$param"
  sed -i "s|^outputDir = .*|outputDir = ${ROOT_RUN}/${CASE_NAME}_factor_${tag}/output|" "$param"
  sed -i "s|^nSteps = .*|nSteps = ${STEPS_PROFILE}|" "$param"
  sed -i "s|^summaryEvery = .*|summaryEvery = ${SUMMARY_EVERY_PROFILE}|" "$param"
  sed -i "s|^dumpStateEvery = .*|dumpStateEvery = 0|" "$param"
  sed -i "s|^projectionEnable = .*|projectionEnable = true|" "$param"
  sed -i "s|^resamplingEnable = .*|resamplingEnable = true|" "$param"
  sed -i "s|^projectionTolerance = .*|projectionTolerance = ${PROJECTION_TOLERANCE}|" "$param"
  echo "$param"
}

run_one() {
  local factor="$1"
  local tag="$2"
  local base_param="$3"
  local mode="$4"        # early or bulk
  local run_kind="$5"    # perf or audit
  local threads="$6"
  local run_param="$ROOT_RUN/params/${CASE_NAME}_factor_${tag}_${mode}_${run_kind}_t${threads}.kv"
  local out_dir="$ROOT_RUN/${CASE_NAME}_factor_${tag}_${mode}_${run_kind}_t${threads}/output"
  local phase_csv="$ROOT_RUN/logs/phase_factor_${tag}_${mode}_${run_kind}_t${threads}.csv"
  local audit_csv="$ROOT_RUN/logs/audit_factor_${tag}_${mode}_${run_kind}_t${threads}.csv"
  local stdout="$ROOT_RUN/logs/${CASE_NAME}_factor_${tag}_${mode}_${run_kind}_t${threads}.stdout"
  cp "$base_param" "$run_param"
  sed -i "s|^numThreads = .*|numThreads = ${threads}|" "$run_param"
  sed -i "s|^outputDir = .*|outputDir = ${out_dir}|" "$run_param"
  rm -f "$phase_csv" "$audit_csv"
  export OMP_NUM_THREADS="$threads"
  export MPCD_TIMING_CSV="$phase_csv"
  export MPCD_TIMING_EVERY="$TIMING_EVERY"
  unset MPCD_Q6_TIMING_CSV || true
  unset MPCD_Q6_TIMING_EVERY || true
  unset MPCD_DISABLE_RESAMPLING_FLUID_SLOTS || true
  unset MPCD_DISABLE_EARLY_RESAMPLING_POOL || true
  if [[ "$mode" == "early" ]]; then
    export MPCD_DISABLE_BULK_OPERATOR_FLUID_SLOTS=1
  else
    unset MPCD_DISABLE_BULK_OPERATOR_FLUID_SLOTS || true
  fi
  if [[ "$run_kind" == "audit" ]]; then
    export MPCD_PARTICLE_AUDIT_CSV="$audit_csv"
    export MPCD_PARTICLE_AUDIT_EVERY="$AUDIT_EVERY"
  else
    unset MPCD_PARTICLE_AUDIT_CSV || true
    unset MPCD_PARTICLE_AUDIT_EVERY || true
  fi
  echo "[0206a-run] factor=$factor mode=$mode run=$run_kind threads=$threads phase=$phase_csv audit=$audit_csv"
  /usr/bin/time -f "__TIME_ROW__,${factor},${mode},${run_kind},${threads},%e,%U,%S,%M,${phase_csv},${audit_csv},${stdout}" \
    "$BIN" "$run_param" \
    > "$stdout" \
    2> "$ROOT_RUN/logs/${CASE_NAME}_factor_${tag}_${mode}_${run_kind}_t${threads}.time"
  grep '^__TIME_ROW__,' "$ROOT_RUN/logs/${CASE_NAME}_factor_${tag}_${mode}_${run_kind}_t${threads}.time" | sed 's/^__TIME_ROW__,//' >> "$GLOBAL_CSV"
}

for factor in $INACTIVE_FACTORS; do
  tag="$(make_factor_tag "$factor")"
  param="$(make_param_for_factor "$factor" "$tag")"
  for threads in $THREADS_LIST; do
    for mode in $MODES_LIST; do
      run_one "$factor" "$tag" "$param" "$mode" perf "$threads"
      if [[ "$AUDIT_ENABLE" != "0" ]]; then
        run_one "$factor" "$tag" "$param" "$mode" audit "$threads"
      fi
    done
  done
done

python3 - "$GLOBAL_CSV" <<'PY'
import csv, sys
from pathlib import Path
rows=list(csv.DictReader(open(sys.argv[1], newline='')))
print('\n[0206a-summary] wall by inactive factor')
for r in rows:
    if r['run_kind'] == 'perf':
        print(f"factor={r['inactive_factor']} mode={r['mode']} threads={r['threads']} wall={float(r['elapsed']):.6g}s")

def phase_sum(path):
    p=Path(path)
    if not p.exists(): return {}
    rr=list(csv.DictReader(open(p, newline='')))
    if not rr: return {}
    out={}
    for k in rr[0].keys():
        if k == 'step': continue
        try:
            out[k]=sum(float(row[k]) for row in rr)
        except Exception:
            pass
    return out

print('\n[0206a-summary] phase slopes by factor, perf rows')
keys=['total','stream','boundary','resamp_pool0','collision','q6','virial','thermostat','resamp_deposit0','resamp_deposit_edit','resamp_velocity_refresh']
for r in rows:
    if r['run_kind'] != 'perf': continue
    ph=phase_sum(r['phase_csv'])
    vals=' '.join(f"{k}={ph.get(k,0.0):.6g}" for k in keys if k in ph)
    print(f"factor={r['inactive_factor']} mode={r['mode']} threads={r['threads']} {vals}")

print('\n[0206a-summary] audit scans by factor')
for r in rows:
    if r['run_kind'] != 'audit': continue
    p=Path(r['audit_csv'])
    if not p.exists(): continue
    rr=list(csv.DictReader(open(p, newline='')))
    if not rr: continue
    n=len(rr); npart=float(rr[0]['n_particles']); cells=float(rr[0]['n_cells'])
    def mean(name): return sum(float(x[name]) for x in rr)/n
    print(f"factor={r['inactive_factor']} mode={r['mode']} threads={r['threads']} sampled_steps={n} "
          f"n_particles={npart:.0f} n_cells={cells:.0f} "
          f"cell_index_per_particle={mean('cell_index_from_position_calls')/npart:.4f} "
          f"fluid_checks_per_particle={mean('is_fluid_particle_calls')/npart:.4f} "
          f"role_value_per_particle={mean('particle_role_value_calls')/npart:.4f}")
PY
