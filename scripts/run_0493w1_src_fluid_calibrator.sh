#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434

CASE_LABEL=src_fluid_calibrator_0493w1
BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}"
RUN_ROOT="${RUN_ROOT:-runs/0493w1_src_fluid_calibrator}"

Lx="${Lx:-1.0}"
Ly="${Ly:-1.0}"
NX="${NX:-64}"
NY="${NY:-64}"
GAMMA="${GAMMA:-20}"
DT="${DT:-0.001}"
KBT="${KBT:-0.01}"
PARTICLE_MASS="${PARTICLE_MASS:-1.0}"
SEED="${SEED:-493201}"

ROTATION_ANGLE="${ROTATION_ANGLE:-2.0943951023931953}"
RANDOM_ROTATION_SIGN="${RANDOM_ROTATION_SIGN:-true}"
GRID_SHIFT_ENABLE="${GRID_SHIFT_ENABLE:-true}"
THERMOSTAT_ENABLE="${THERMOSTAT_ENABLE:-false}"
THERMOSTAT_MODE="${THERMOSTAT_MODE:-cell_relative_rescale}"
THERMOSTAT_EVERY="${THERMOSTAT_EVERY:-1}"
THERMOSTAT_TARGET_KBT="${THERMOSTAT_TARGET_KBT:-$KBT}"
THERMOSTAT_MIN_PARTICLES="${THERMOSTAT_MIN_PARTICLES:-3}"

TG_MODE_X="${TG_MODE_X:-1}"
TG_MODE_Y="${TG_MODE_Y:-1}"
TG_AMPLITUDE="${TG_AMPLITUDE:-}"
TG_STEPS="${TG_STEPS:-2000}"
TG_DUMP_COUNT="${TG_DUMP_COUNT:-50}"

SOUND_MODE_X="${SOUND_MODE_X:-2}"
SOUND_DENSITY_AMPLITUDE="${SOUND_DENSITY_AMPLITUDE:-0.08}"
# fix3: average several independent thermal realizations and fit cumulative
# longitudinal balances. Warm/physical candidate fluids need only a short run.
SOUND_STEPS="${SOUND_STEPS:-1200}"
SOUND_DUMP_COUNT="${SOUND_DUMP_COUNT:-120}"
SOUND_REPLICATES="${SOUND_REPLICATES:-4}"
SOUND_SEED_STRIDE="${SOUND_SEED_STRIDE:-1009}"

MSD_GRID_MODE="${MSD_GRID_MODE:-cell_equivalent}"
MSD_MAX_NX="${MSD_MAX_NX:-64}"
MSD_MAX_NY="${MSD_MAX_NY:-64}"
MSD_STEPS="${MSD_STEPS:-3000}"
MSD_DUMP_COUNT="${MSD_DUMP_COUNT:-60}"
MSD_SAMPLE_PARTICLES="${MSD_SAMPLE_PARTICLES:-20000}"

CHARACTERISTIC_U="${CHARACTERISTIC_U:--1}"
CHARACTERISTIC_L="${CHARACTERISTIC_L:--1}"
MAX_DUMP_GB="${MAX_DUMP_GB:-5.0}"
ALLOW_LARGE_DUMPS="${ALLOW_LARGE_DUMPS:-0}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
ANALYZE_ONLY="${ANALYZE_ONLY:-0}"
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
THREADS="${THREADS:-8}"

readarray -t DERIVED < <(
python3 - "$Lx" "$Ly" "$NX" "$NY" "$DT" "$KBT" "$PARTICLE_MASS" \
  "$TG_AMPLITUDE" "$TG_STEPS" "$TG_DUMP_COUNT" "$SOUND_MODE_X" \
  "$SOUND_STEPS" "$SOUND_DUMP_COUNT" "$SOUND_REPLICATES" "$MSD_GRID_MODE" \
  "$MSD_MAX_NX" "$MSD_MAX_NY" "$MSD_STEPS" "$MSD_DUMP_COUNT" <<'PY_DERIVED'
import math
import sys

Lx, Ly = float(sys.argv[1]), float(sys.argv[2])
nx, ny = int(sys.argv[3]), int(sys.argv[4])
dt, kbt, mass = map(float, sys.argv[5:8])
requested_tg = sys.argv[8]
tg_steps, tg_count = int(sys.argv[9]), int(sys.argv[10])
sound_mode = int(sys.argv[11])
sound_steps = int(sys.argv[12])
sound_count = int(sys.argv[13])
sound_replicates = int(sys.argv[14])
grid_mode = sys.argv[15]
max_nx, max_ny = int(sys.argv[16]), int(sys.argv[17])
msd_steps, msd_count = int(sys.argv[18]), int(sys.argv[19])
if sound_replicates < 1:
    raise SystemExit('SOUND_REPLICATES must be positive')

cs_iso = math.sqrt(kbt / mass)
cs_ad_2d = math.sqrt(2 * kbt / mass)
tg_amplitude = float(requested_tg) if requested_tg else 0.10 * cs_ad_2d
# Ideal proxies are printed for context only.  fix2 does not use them to
# size the run or identify c_s.
if sound_steps < 1:
    raise SystemExit('SOUND_STEPS must be positive')

if grid_mode == 'full':
    msd_nx, msd_ny = nx, ny
elif grid_mode == 'cell_equivalent':
    msd_nx, msd_ny = min(nx, max_nx), min(ny, max_ny)
else:
    raise SystemExit('MSD_GRID_MODE must be full or cell_equivalent')
msd_lx = Lx * msd_nx / nx
msd_ly = Ly * msd_ny / ny

def cadence(steps, count):
    return max(1, int(math.ceil(steps / max(1, count))))

values = (
    tg_amplitude,
    cs_iso,
    cs_ad_2d,
    sound_steps,
    cadence(tg_steps, tg_count),
    msd_nx,
    msd_ny,
    msd_lx,
    msd_ly,
    cadence(msd_steps, msd_count),
    cadence(sound_steps, sound_count),
)
for value in values:
    print(value)
PY_DERIVED
)

TG_AMPLITUDE=${DERIVED[0]}
CS_ISOTHERMAL_PROXY=${DERIVED[1]}
CS_ADIABATIC_2D_PROXY=${DERIVED[2]}
SOUND_STEPS=${DERIVED[3]}
TG_DUMP_EVERY=${DERIVED[4]}
MSD_NX=${DERIVED[5]}
MSD_NY=${DERIVED[6]}
MSD_LX=${DERIVED[7]}
MSD_LY=${DERIVED[8]}
MSD_DUMP_EVERY=${DERIVED[9]}
SOUND_DUMP_EVERY=${DERIVED[10]}

export OMP_NUM_THREADS="$THREADS" LIVE_PROGRESS
INACTIVE_SLOTS=0
SUMMARY_ROLE_FILTER=fluid
DUMP_ROLE_FILTER=fluid
SPECIES_RESAMPLING_ENABLE=false
WEIGHTED_RESAMPLING_ENABLE_OVERRIDE=false
CUDA_EMPTY_REFILL_ENABLE_OVERRIDE=false
RESAMPLING_THERMAL_RENORMALIZATION_ENABLE=false
RESAMPLING_MASS_GUARD_ENABLE=false
PROJECTION_BACKEND=cuda
PROJECTION_OPERATOR=auto_fv_cg
PROJECTION_MAX_ITERATIONS=100
PROJECTION_TOLERANCE=1e-12
PROJECTION_MOMENTUM_CORRECTION_ENABLE=true
Q6_PROJECTION_STRENGTH=1.0
LIVE_VIS_ENABLE=0
FILTERED_RECORDING_ENABLE=0
RECORD_ENABLE=false
PARTICLE_TYPE_FILTER=-1
suite_defaults_common_0434
suite_compute_derived_0434

python3 - \
  "$Lx" "$Ly" "$NX" "$NY" "$GAMMA" "$DT" "$KBT" "$PARTICLE_MASS" \
  "$ROTATION_ANGLE" "$RANDOM_ROTATION_SIGN" "$GRID_SHIFT_ENABLE" \
  "$THERMOSTAT_ENABLE" "$THERMOSTAT_MODE" "$THERMOSTAT_EVERY" \
  "$THERMOSTAT_TARGET_KBT" "$THERMOSTAT_MIN_PARTICLES" \
  "$TG_MODE_X" "$TG_MODE_Y" "$TG_AMPLITUDE" "$TG_STEPS" "$TG_DUMP_EVERY" \
  "$SOUND_MODE_X" "$SOUND_DENSITY_AMPLITUDE" "$SOUND_STEPS" "$SOUND_DUMP_EVERY" \
  "$SOUND_REPLICATES" "$SOUND_SEED_STRIDE" "$CS_ISOTHERMAL_PROXY" "$CS_ADIABATIC_2D_PROXY" \
  "$MSD_LX" "$MSD_LY" "$MSD_NX" "$MSD_NY" "$MSD_STEPS" "$MSD_DUMP_EVERY" \
  "$MSD_SAMPLE_PARTICLES" "$MAX_DUMP_GB" "$ALLOW_LARGE_DUMPS" \
  "$CHARACTERISTIC_U" "$CHARACTERISTIC_L" <<'PY_PREFLIGHT'
import math
import sys

(
    Lx, Ly, nx, ny, gamma, dt, kbt, mass,
    angle, random_sign, grid_shift,
    thermostat, thermostat_mode, thermostat_every,
    thermostat_target, thermostat_min,
    tg_mode_x, tg_mode_y, tg_amplitude, tg_steps, tg_dump,
    sound_mode, sound_amplitude, sound_steps, sound_dump,
    sound_replicates, sound_seed_stride, cs_iso, cs_ad,
    msd_lx, msd_ly, msd_nx, msd_ny, msd_steps, msd_dump,
    msd_sample, max_gb, allow_large, characteristic_u, characteristic_l,
) = sys.argv[1:]

Lx, Ly, dt, kbt, mass = map(float, (Lx, Ly, dt, kbt, mass))
nx, ny, gamma = map(int, (nx, ny, gamma))
angle = float(angle)
thermostat_every = int(thermostat_every)
thermostat_target = float(thermostat_target)
thermostat_min = int(thermostat_min)
tg_mode_x, tg_mode_y = int(tg_mode_x), int(tg_mode_y)
tg_amplitude = float(tg_amplitude)
tg_steps, tg_dump = int(tg_steps), int(tg_dump)
sound_mode = int(sound_mode)
sound_amplitude = float(sound_amplitude)
sound_steps, sound_dump = int(sound_steps), int(sound_dump)
sound_replicates, sound_seed_stride = int(sound_replicates), int(sound_seed_stride)
cs_iso, cs_ad = map(float, (cs_iso, cs_ad))
msd_lx, msd_ly = float(msd_lx), float(msd_ly)
msd_nx, msd_ny = int(msd_nx), int(msd_ny)
msd_steps, msd_dump, msd_sample = int(msd_steps), int(msd_dump), int(msd_sample)
max_gb = float(max_gb)
allow_large = allow_large == '1'
characteristic_u, characteristic_l = float(characteristic_u), float(characteristic_l)

def boolean(name, value):
    if value.lower() not in ('true', 'false'):
        raise SystemExit(f'[0493w1] {name} must be true or false')
    return value.lower() == 'true'

random_sign_b = boolean('RANDOM_ROTATION_SIGN', random_sign)
grid_shift_b = boolean('GRID_SHIFT_ENABLE', grid_shift)
thermostat_b = boolean('THERMOSTAT_ENABLE', thermostat)

if min(Lx, Ly, nx, ny, gamma, dt, kbt, mass) <= 0:
    raise SystemExit('[0493w1] invalid geometry/population/thermal parameter')
if min(tg_steps, tg_dump, sound_steps, sound_dump, sound_replicates, msd_steps, msd_dump) < 1:
    raise SystemExit('[0493w1] steps and dump cadences must be positive')
if thermostat_every < 1 or thermostat_min < 1:
    raise SystemExit('[0493w1] invalid thermostat cadence/minimum population')
if not 0 < sound_amplitude < 0.2:
    raise SystemExit('[0493w1] SOUND_DENSITY_AMPLITUDE must be in (0,0.2)')
if sound_mode * 8 > nx:
    raise SystemExit('[0493w1] sound wavelength requires at least 8 cells')

ax = Lx / nx
ay = Ly / ny
if abs(ax - ay) / max(ax, ay) > 0.02:
    raise SystemExit(
        f'[0493w1] collision cells must be nearly square: ax={ax} ay={ay}'
    )

def dumps(steps, every):
    return 1 + steps // every + (0 if steps % every == 0 else 1)

n_full = nx * ny * gamma
n_msd = msd_nx * msd_ny * gamma
volume = 45 * (
    n_full * (dumps(tg_steps, tg_dump) + sound_replicates * dumps(sound_steps, sound_dump))
    + n_msd * dumps(msd_steps, msd_dump)
) + 360
volume_gb = volume / 1e9
sound_duration = sound_steps * dt
period_iso = Lx / (sound_mode * cs_iso)
period_ad = Lx / (sound_mode * cs_ad)
cycles_iso = sound_duration / period_iso
cycles_ad = sound_duration / period_ad
samples_iso = period_iso / (sound_dump * dt)
samples_ad = period_ad / (sound_dump * dt)
variant = 'thermostatted_src' if thermostat_b else 'raw_src'

print('===== 0493w1 PREFLIGHT =====')
print(f'fluidVariant={variant} q6=false resampling=false')
print(f'domain Lx/Ly={Lx:.9g}/{Ly:.9g} grid={nx}x{ny} cell={ax:.9g}x{ay:.9g} gamma={gamma} N={n_full}')
print(f'thermal dt={dt:.9g} kBT={kbt:.9g} mass={mass:.9g} csIsoProxy={cs_iso:.9g} csAdiabatic2DProxy={cs_ad:.9g}')
print(f'collision rotation={angle:.12g}rad/{angle*180/math.pi:.9g}deg randomSign={str(random_sign_b).lower()} gridShift={str(grid_shift_b).lower()}')
print(f'thermostat enable={str(thermostat_b).lower()} mode={thermostat_mode} every={thermostat_every} targetKBT={thermostat_target:.9g} minParticles={thermostat_min}')
print(f'TG mode={tg_mode_x},{tg_mode_y} amplitude={tg_amplitude:.9g} steps={tg_steps} dumpEvery={tg_dump} duration={tg_steps*dt:.9g}')
print(f'sound initialization=standing_density_zero_velocity modeX={sound_mode} wavelength={Lx/sound_mode:.9g} wavelengthCells={nx/sound_mode:.9g} densityAmplitude={sound_amplitude:.9g}')
print('sound estimator=ensemble_cumulative_hydrodynamic_regression equations=continuity+longitudinal_momentum')
print(f'sound replicates={sound_replicates} seedStride={sound_seed_stride} steps={sound_steps} dumpEvery={sound_dump} duration={sound_duration:.9g} intervals={dumps(sound_steps,sound_dump)-1} proxyCyclesIso/Ad2D={cycles_iso:.6g}/{cycles_ad:.6g} samplesPerCycleIso/Ad2D={samples_iso:.6g}/{samples_ad:.6g}')
print('sound note=independent thermal replicas are averaged before cumulative regression; full acoustic cycle not required')
print(f'MSD grid={msd_nx}x{msd_ny} box={msd_lx:.9g}x{msd_ly:.9g} steps={msd_steps} dumpEvery={msd_dump} sampleParticles={min(msd_sample,n_msd)}')
print(f'estimatedDumpVolume={volume_gb:.3f} GB limit={max_gb:.3f} GB')
print(f'particleSteps={(n_full*(tg_steps+sound_replicates*sound_steps)+n_msd*msd_steps):.6e}')
if characteristic_u > 0 and characteristic_l > 0:
    print(f'flowScale U={characteristic_u:.9g} L={characteristic_l:.9g}; measured Re/Ma/Pe/Kn will be reported')
else:
    print('flowScale not supplied; set CHARACTERISTIC_U and CHARACTERISTIC_L for Re/Ma/Pe/Kn')
if dumps(sound_steps, sound_dump) - 1 < 40:
    print('[0493w1] WARNING fewer than 40 acoustic regression intervals; increase SOUND_DUMP_COUNT')
if samples_ad < 12:
    print(f'[0493w1] WARNING only {samples_ad:.6g} samples per fastest-proxy cycle; increase SOUND_DUMP_COUNT')
if nx / sound_mode < 16:
    print(f'[0493w1] WARNING sound wavelength has only {nx/sound_mode:.6g} cells (<16)')
if volume_gb > max_gb and not allow_large:
    raise SystemExit(
        '[0493w1] estimated dump volume exceeds MAX_DUMP_GB; '
        'reduce dump counts/use cell_equivalent or set ALLOW_LARGE_DUMPS=1'
    )
PY_PREFLIGHT

if [[ "$ANALYZE_ONLY" != 1 ]]; then
  [[ "$CLEAN_RUN_ROOT" == 1 ]] && rm -rf "$RUN_ROOT"
  mkdir -p "$RUN_ROOT"/{init,analysis,logs}
fi
if [[ "$PREFLIGHT_ONLY" == 1 ]]; then
  echo '[0493w1] PREFLIGHT_ONLY=1; no simulation launched'
  exit 0
fi
if [[ "$ANALYZE_ONLY" != 1 ]]; then
  suite_ensure_binary_0434
fi

make_state() {
  local kind=$1 out=$2 lx=$3 ly=$4 nx=$5 ny=$6 seed=$7
  python3 scripts/generate_0493w1_src_fluid_calibrator_states.py \
    --case "$kind" --output "$out" --Lx "$lx" --Ly "$ly" \
    --Nx "$nx" --Ny "$ny" --gamma "$GAMMA" --dt "$DT" --kBT "$KBT" \
    --mass "$PARTICLE_MASS" --seed "$seed" \
    --tg-mode-x "$TG_MODE_X" --tg-mode-y "$TG_MODE_Y" \
    --tg-amplitude "$TG_AMPLITUDE" --sound-mode-x "$SOUND_MODE_X" \
    --sound-density-amplitude "$SOUND_DENSITY_AMPLITUDE"
}

write_params() {
  local kind=$1 state=$2 lx=$3 ly=$4 nx=$5 ny=$6 steps=$7 dump=$8
  local dir="$RUN_ROOT/$kind"
  mkdir -p "$dir"/{params,output,logs}
  SUMMARY_EVERY="$dump"
  DUMP_STATE_EVERY="$dump"
  cat > "$dir/params/params_0493w1.kv" <<EOF_PARAMS
inputState = $state
outputDir = $dir/output
Lx = $lx
Ly = $ly
Nx = $nx
Ny = $ny
dt = $DT
nSteps = $steps
bodyAccelerationX = 0.0
bodyAccelerationY = 0.0
keepMeanFlowEnable = false
taylorGreenForcingEnable = false
bcLeft = periodic
bcRight = periodic
bcBottom = periodic
bcTop = periodic
bcX = periodic
bcY = periodic
speciesRegistryEnable = false
speciesQ6Enable = false
EOF_PARAMS
  suite_write_common_params_0434 src >> "$dir/params/params_0493w1.kv"
  printf '%s\n' "$dir/params/params_0493w1.kv"
}

run_one() {
  local kind=$1 state=$2 lx=$3 ly=$4 nx=$5 ny=$6 steps=$7 dump=$8
  suite_export_cuda_flags_0434 src periodic
  local params
  params=$(write_params "$kind" "$state" "$lx" "$ly" "$nx" "$ny" "$steps" "$dump")
  suite_preflight_run_ok_0492 "$params"
  echo "[0493w1] run=$kind grid=${nx}x${ny} steps=$steps dumpEvery=$dump"
  set +e
  /usr/bin/time -o "$RUN_ROOT/$kind/logs/time_0493w1.txt" \
    -f 'elapsed=%e user=%U sys=%S' \
    "$BIN" "$params" 2>&1 | tee "$RUN_ROOT/$kind/logs/run_0493w1.log"
  rc=${PIPESTATUS[0]}
  set -e
  [[ $rc -eq 0 ]] || {
    echo "[0493w1] ERROR $kind rc=$rc" >&2
    exit "$rc"
  }
}

if [[ "$ANALYZE_ONLY" != 1 ]]; then
  TG_STATE="$RUN_ROOT/init/tg_0493w1.smpcd"
  MSD_STATE="$RUN_ROOT/init/msd_0493w1.smpcd"
  make_state tg "$TG_STATE" "$Lx" "$Ly" "$NX" "$NY" "$SEED"
  make_state msd "$MSD_STATE" "$MSD_LX" "$MSD_LY" "$MSD_NX" "$MSD_NY" "$((SEED + 2000003))"
  run_one tg "$TG_STATE" "$Lx" "$Ly" "$NX" "$NY" "$TG_STEPS" "$TG_DUMP_EVERY"
  for ((rep=0; rep<SOUND_REPLICATES; ++rep)); do
    printf -v rep_label 'sound_rep%03d' "$rep"
    rep_state="$RUN_ROOT/init/${rep_label}_0493w1.smpcd"
    rep_seed=$((SEED + 500009 + rep * SOUND_SEED_STRIDE))
    make_state sound "$rep_state" "$Lx" "$Ly" "$NX" "$NY" "$rep_seed"
    run_one "$rep_label" "$rep_state" "$Lx" "$Ly" "$NX" "$NY" "$SOUND_STEPS" "$SOUND_DUMP_EVERY"
  done
  run_one msd "$MSD_STATE" "$MSD_LX" "$MSD_LY" "$MSD_NX" "$MSD_NY" "$MSD_STEPS" "$MSD_DUMP_EVERY"
fi

python3 scripts/analyze_0493w1_src_fluid_calibrator.py \
  --root "$RUN_ROOT" --Lx "$Lx" --Ly "$Ly" --Nx "$NX" --Ny "$NY" \
  --gamma "$GAMMA" --dt "$DT" --kBT "$KBT" --mass "$PARTICLE_MASS" \
  --rotation-angle "$ROTATION_ANGLE" \
  --random-rotation-sign "$RANDOM_ROTATION_SIGN" \
  --grid-shift-enable "$GRID_SHIFT_ENABLE" \
  --thermostat-enable "$THERMOSTAT_ENABLE" --thermostat-mode "$THERMOSTAT_MODE" \
  --thermostat-every "$THERMOSTAT_EVERY" \
  --thermostat-target-kBT "$THERMOSTAT_TARGET_KBT" \
  --thermostat-min-particles "$THERMOSTAT_MIN_PARTICLES" \
  --tg-mode-x "$TG_MODE_X" --tg-mode-y "$TG_MODE_Y" \
  --tg-amplitude "$TG_AMPLITUDE" --sound-mode-x "$SOUND_MODE_X" \
  --sound-density-amplitude "$SOUND_DENSITY_AMPLITUDE" \
  --sound-replicates "$SOUND_REPLICATES" \
  --msd-Lx "$MSD_LX" --msd-Ly "$MSD_LY" --msd-Nx "$MSD_NX" --msd-Ny "$MSD_NY" \
  --msd-sample-particles "$MSD_SAMPLE_PARTICLES" \
  --characteristic-U "$CHARACTERISTIC_U" --characteristic-L "$CHARACTERISTIC_L"
