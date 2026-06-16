#!/usr/bin/env bash
set -euo pipefail

# 0203a A/B for resampling fluidSlots scan path with explicit inactive slots.
# slots: use resamplingPool.fluidSlots in deposits/refresh/index builders.
# legacy: set MPCD_DISABLE_RESAMPLING_FLUID_SLOTS=1 to force full state.Np scans.
# Both modes keep the 0201b cellId reuse path enabled unless explicitly disabled outside.
# The script runs both performance rows without particle audit and optional audit rows
# to verify that cell_index_from_position calls drop as intended.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

ROOT_RUN="${ROOT_RUN:-runs/profile_resampling_fluid_slots_inactive_0203a}"
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
INACTIVE_SLOTS="${INACTIVE_SLOTS:-auto}"
INACTIVE_FACTOR="${INACTIVE_FACTOR:-1.0}"

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

BIN="build/src_mpcd_base_resampling_fluid_slots_inactive_0203a"
echo "[0203a-build] $BIN"
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

mkdir -p "$ROOT_RUN/init"
STATE_FILE="$ROOT_RUN/init/taylor_green_${NX}x${NY}_g${GAMMA}_seed${SEED}_inactive_${INACTIVE_SLOTS}_factor_${INACTIVE_FACTOR}.smpcd"
python3 scripts/augment_smpcd_inactive_slots_0203a.py \
  "$STATE_FILE_ACTIVE" "$STATE_FILE" "$INACTIVE_SLOTS" "$INACTIVE_FACTOR"
PARAM="$ROOT_RUN/params/${CASE_NAME}.kv"
cp "$TEMPLATE" "$PARAM"
sed -i "s|^inputState = .*|inputState = ${STATE_FILE}|" "$PARAM"
sed -i "s|^outputDir = .*|outputDir = ${ROOT_RUN}/${CASE_NAME}/output|" "$PARAM"
sed -i "s|^nSteps = .*|nSteps = ${STEPS_PROFILE}|" "$PARAM"
sed -i "s|^summaryEvery = .*|summaryEvery = ${SUMMARY_EVERY_PROFILE}|" "$PARAM"
sed -i "s|^dumpStateEvery = .*|dumpStateEvery = 0|" "$PARAM"
sed -i "s|^projectionEnable = .*|projectionEnable = true|" "$PARAM"
sed -i "s|^resamplingEnable = .*|resamplingEnable = true|" "$PARAM"
sed -i "s|^projectionTolerance = .*|projectionTolerance = ${PROJECTION_TOLERANCE}|" "$PARAM"

GLOBAL_CSV="$ROOT_RUN/logs/timings_resampling_fluid_slots_inactive_0203a.csv"
echo "mode,run_kind,threads,elapsed,user,sys,maxrss_kb,phase_csv,audit_csv,stdout" > "$GLOBAL_CSV"

run_one() {
  local mode="$1"        # slots or legacy
  local run_kind="$2"    # perf or audit
  local threads="$3"
  local run_param="$ROOT_RUN/params/${CASE_NAME}_${mode}_${run_kind}_t${threads}.kv"
  local out_dir="$ROOT_RUN/${CASE_NAME}_${mode}_${run_kind}_t${threads}/output"
  local phase_csv="$ROOT_RUN/logs/phase_${mode}_${run_kind}_t${threads}.csv"
  local audit_csv="$ROOT_RUN/logs/audit_${mode}_${run_kind}_t${threads}.csv"
  local stdout="$ROOT_RUN/logs/${CASE_NAME}_${mode}_${run_kind}_t${threads}.stdout"
  cp "$PARAM" "$run_param"
  sed -i "s|^numThreads = .*|numThreads = ${threads}|" "$run_param"
  sed -i "s|^outputDir = .*|outputDir = ${out_dir}|" "$run_param"
  rm -f "$phase_csv" "$audit_csv"
  export OMP_NUM_THREADS="$threads"
  export MPCD_TIMING_CSV="$phase_csv"
  export MPCD_TIMING_EVERY="$TIMING_EVERY"
  unset MPCD_Q6_TIMING_CSV || true
  unset MPCD_Q6_TIMING_EVERY || true
  if [[ "$mode" == "legacy" ]]; then
    export MPCD_DISABLE_RESAMPLING_FLUID_SLOTS=1
  else
    unset MPCD_DISABLE_RESAMPLING_FLUID_SLOTS || true
  fi
  if [[ "$run_kind" == "audit" ]]; then
    export MPCD_PARTICLE_AUDIT_CSV="$audit_csv"
    export MPCD_PARTICLE_AUDIT_EVERY="$AUDIT_EVERY"
  else
    unset MPCD_PARTICLE_AUDIT_CSV || true
    unset MPCD_PARTICLE_AUDIT_EVERY || true
  fi
  echo "[0203a-run] mode=$mode run=$run_kind threads=$threads phase=$phase_csv audit=$audit_csv"
  /usr/bin/time -f "__TIME_ROW__,${mode},${run_kind},${threads},%e,%U,%S,%M,${phase_csv},${audit_csv},${stdout}" \
    "$BIN" "$run_param" \
    > "$stdout" \
    2> "$ROOT_RUN/logs/${CASE_NAME}_${mode}_${run_kind}_t${threads}.time"
  grep '^__TIME_ROW__,' "$ROOT_RUN/logs/${CASE_NAME}_${mode}_${run_kind}_t${threads}.time" | sed 's/^__TIME_ROW__,//' >> "$GLOBAL_CSV"
}

for threads in $THREADS_LIST; do
  run_one legacy perf "$threads"
  run_one slots perf "$threads"
  if [[ "$AUDIT_ENABLE" != "0" ]]; then
    run_one legacy audit "$threads"
    run_one slots audit "$threads"
  fi
done

python3 - "$GLOBAL_CSV" <<'PY'
import csv, re, sys
from pathlib import Path

rows=list(csv.DictReader(open(sys.argv[1], newline='')))
print('\n[0203a-summary]')
for r in rows:
    print(f"mode={r['mode']} kind={r['run_kind']} threads={r['threads']} wall={float(r['elapsed']):.6g}s phase={r['phase_csv']}")

print('\n[0203a-summary] perf comparison')
perf={(r['threads'],r['mode']):r for r in rows if r['run_kind']=='perf'}
for threads in sorted(set(k[0] for k in perf)):
    legacy=perf.get((threads,'legacy'))
    slots=perf.get((threads,'slots'))
    if legacy and slots:
        lw=float(legacy['elapsed']); cw=float(slots['elapsed'])
        print(f"threads={threads} wall legacy={lw:.6g}s slots={cw:.6g}s speedup={lw/cw if cw else 0:.4g}")

def phase_sum(path):
    p=Path(path)
    if not p.exists():
        return {}
    out={}
    rr=list(csv.DictReader(open(p, newline='')))
    if not rr:
        return out
    for k in rr[0].keys():
        if k=='step':
            continue
        vals=[]
        ok=True
        for row in rr:
            try: vals.append(float(row[k]))
            except Exception:
                ok=False; break
        if ok: out[k]=sum(vals)
    return out

print('\n[0203a-summary] phase comparison, perf rows')
for threads in sorted(set(k[0] for k in perf)):
    legacy=perf.get((threads,'legacy'))
    slots=perf.get((threads,'slots'))
    if not legacy or not slots:
        continue
    lph=phase_sum(legacy['phase_csv'])
    cph=phase_sum(slots['phase_csv'])
    for key in ['total','resamp_deposit0','resamp_deposit_edit','resamp_deposit_remap','resamp_velocity_refresh','q6','collision','thermostat']:
        if key in lph and key in cph:
            print(f"threads={threads} {key:24s} legacy={lph[key]:.6g}s slots={cph[key]:.6g}s ratio={lph[key]/cph[key] if cph[key] else 0:.4g}")

print('\n[0203a-summary] audit particle-scan comparison')
audit={(r['threads'],r['mode']):r for r in rows if r['run_kind']=='audit'}
for threads in sorted(set(k[0] for k in audit)):
    legacy=audit.get((threads,'legacy'))
    slots=audit.get((threads,'slots'))
    if not legacy or not slots:
        continue
    for label,r in [('legacy',legacy),('slots',slots)]:
        p=Path(r['audit_csv'])
        if not p.exists():
            print(f"missing audit: {p}")
            continue
        rr=list(csv.DictReader(open(p, newline='')))
        n=len(rr)
        npart=float(rr[0]['n_particles']) if rr else 0.0
        cell=sum(float(x['cell_index_from_position_calls']) for x in rr)/n if n else 0.0
        fluid=sum(float(x['is_fluid_particle_calls']) for x in rr)/n if n else 0.0
        role=sum(float(x['particle_role_value_calls']) for x in rr)/n if n else 0.0
        print(f"threads={threads} mode={label} sampled_steps={n} cell_index_per_step={cell:.0f} cell_index_per_particle={cell/npart if npart else 0:.4f} fluid_checks_per_particle={fluid/npart if npart else 0:.4f} role_value_per_particle={role/npart if npart else 0:.4f}")
PY
