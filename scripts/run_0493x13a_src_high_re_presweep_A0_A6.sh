#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

# 0493x13a -- generic SRC-only high-Re presweep A0-A6.
# No source-code modification, no Q6, no resampling, no splash/JFM assumptions.
# The existing 0493w1 calibrator remains the source of TG/MSD/sound measurements.

SWEEP_ROOT="${SWEEP_ROOT:-runs/0493x13a_src_high_re_presweep_A0_A6}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
ANALYZE_ONLY="${ANALYZE_ONLY:-0}"
CLEAN_SWEEP_ROOT="${CLEAN_SWEEP_ROOT:-1}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
THREADS="${THREADS:-8}"
CASES="${CASES:-A0,A1,A2,A3,A4,A5,A6}"

# Canonical A campaign: keep the collision cell, temperature, occupancy and mass fixed.
CELL_SIZE="0.00390625"       # 1/256
CAL_NX="64"
CAL_NY="64"
GAMMA="20"
KBT="0.125"
PARTICLE_MASS="1.0"
SEED="4931301"

# Preserve the qualified thermostatted SRC variant used by the previous 0493w1 campaign.
THERMOSTAT_ENABLE="true"
THERMOSTAT_MODE="cell_relative_rescale"
THERMOSTAT_EVERY="1"
THERMOSTAT_MIN_PARTICLES="3"

# Equal physical observation windows across A0-A6.
TG_TIME="${TG_TIME:-4.0}"
SOUND_TIME="${SOUND_TIME:-2.4}"
MSD_TIME="${MSD_TIME:-5.0}"
TG_DUMP_COUNT="${TG_DUMP_COUNT:-80}"
SOUND_DUMP_COUNT="${SOUND_DUMP_COUNT:-120}"
SOUND_REPLICATES="${SOUND_REPLICATES:-2}"
MSD_DUMP_COUNT="${MSD_DUMP_COUNT:-60}"
MSD_SAMPLE_PARTICLES="${MSD_SAMPLE_PARTICLES:-20000}"

# Longest available hydrodynamic wavelength in the 64-cell calibration box.
SOUND_MODE_X="1"
SOUND_DENSITY_AMPLITUDE="0.08"

# Intentionally application-independent. x13a's collector reports intrinsic Re/Ma per L/h cell.
CHARACTERISTIC_U="-1"
CHARACTERISTIC_L="-1"

command -v python3 >/dev/null || { echo '[0493x13a] python3 not found' >&2; exit 2; }
[[ -x scripts/run_0493w1_src_fluid_calibrator.sh || -f scripts/run_0493w1_src_fluid_calibrator.sh ]] || {
  echo '[0493x13a] missing scripts/run_0493w1_src_fluid_calibrator.sh' >&2
  exit 2
}
[[ -f scripts/analyze_0493x13a_src_high_re_presweep.py ]] || {
  echo '[0493x13a] missing scripts/analyze_0493x13a_src_high_re_presweep.py' >&2
  exit 2
}

# A cases are defined by collision angle and target mean thermal flight lambda_mean/h.
# A0's target is the exact lambda/h corresponding to dt=0.002 for the canonical h,kBT,m.
case_spec() {
  case "$1" in
    A0) printf '%s|%s|%s\n' '90'  '0.22687409291590604' 'historical_90deg_reference' ;;
    A1) printf '%s|%s|%s\n' '120' '0.48'                'increase_collision_angle' ;;
    A2) printf '%s|%s|%s\n' '150' '0.95'                'strong_backscattering_local_limit' ;;
    A3) printf '%s|%s|%s\n' '165' '1.32'                'mesoscopic_transition' ;;
    A4) printf '%s|%s|%s\n' '175' '1.50'                'near_pi_moderate_flight' ;;
    A5) printf '%s|%s|%s\n' '175' '2.10'                'near_pi_extended_flight' ;;
    A6) printf '%s|%s|%s\n' '175' '3.00'                'near_pi_boundary_probe' ;;
    *) return 1 ;;
  esac
}

contains_case() {
  local needle=$1 item
  IFS=',' read -ra _requested <<< "$CASES"
  for item in "${_requested[@]}"; do
    [[ "$item" == "$needle" ]] && return 0
  done
  return 1
}

# Validate requested names before changing the run directory.
IFS=',' read -ra REQUESTED <<< "$CASES"
for c in "${REQUESTED[@]}"; do
  case_spec "$c" >/dev/null || {
    echo "[0493x13a] unknown case '$c'; expected comma-separated subset of A0..A6" >&2
    exit 2
  }
done

if [[ "$ANALYZE_ONLY" != 1 && "$PREFLIGHT_ONLY" != 1 && "$CLEAN_SWEEP_ROOT" == 1 ]]; then
  rm -rf "$SWEEP_ROOT"
fi
mkdir -p "$SWEEP_ROOT/analysis"

manifest="$SWEEP_ROOT/manifest_0493x13a.csv"
python3 - "$manifest" "$CELL_SIZE" "$CAL_NX" "$CAL_NY" "$GAMMA" "$KBT" "$PARTICLE_MASS" \
  "$TG_TIME" "$SOUND_TIME" "$MSD_TIME" "$SOUND_REPLICATES" <<'PY_MANIFEST'
import csv, math, sys
from pathlib import Path

out=Path(sys.argv[1]); h=float(sys.argv[2]); nx=int(sys.argv[3]); ny=int(sys.argv[4])
gamma=int(sys.argv[5]); kbt=float(sys.argv[6]); mass=float(sys.argv[7])
t_tg=float(sys.argv[8]); t_sound=float(sys.argv[9]); t_msd=float(sys.argv[10]); sound_reps=int(sys.argv[11])

cases=[
    ('A0',90.0,0.22687409291590604,'historical_90deg_reference'),
    ('A1',120.0,0.48,'increase_collision_angle'),
    ('A2',150.0,0.95,'strong_backscattering_local_limit'),
    ('A3',165.0,1.32,'mesoscopic_transition'),
    ('A4',175.0,1.50,'near_pi_moderate_flight'),
    ('A5',175.0,2.10,'near_pi_extended_flight'),
    ('A6',175.0,3.00,'near_pi_boundary_probe'),
]
vmean=math.sqrt(math.pi*kbt/(2.0*mass))
fg=(gamma-1.0+math.exp(-gamma))/gamma
rows=[]
for label,deg,lam,role in cases:
    rad=math.radians(deg)
    dt=lam*h/vmean
    q=fg*(1.0-math.cos(rad))
    nu_kin=kbt*dt/mass*(1.0/q-0.5)
    nu_col=h*h*q/(12.0*dt)
    nu_srd=nu_kin+nu_col
    tg_steps=max(1, math.ceil(t_tg/dt))
    sound_steps=max(1, math.ceil(t_sound/dt))
    msd_steps=max(1, math.ceil(t_msd/dt))
    n=nx*ny*gamma
    particle_steps=n*(tg_steps+sound_reps*sound_steps+msd_steps)
    rows.append(dict(
        case=label,role=role,gamma=gamma,rotationAngleDeg=deg,rotationAngleRad=rad,
        targetLambdaMeanOverCell=lam,dt=dt,cellSize=h,Nx=nx,Ny=ny,Lx=nx*h,Ly=ny*h,
        kBT=kbt,particleMass=mass,vMeanThermal2D=vmean,fGamma=fg,qCollision=q,
        viscositySRDKinematic=nu_srd,viscositySRDKinetic=nu_kin,viscositySRDCollisional=nu_col,
        tgPhysicalTime=t_tg,tgSteps=tg_steps,soundPhysicalTime=t_sound,soundSteps=sound_steps,
        soundReplicates=sound_reps,msdPhysicalTime=t_msd,msdSteps=msd_steps,
        nominalParticleCount=n,estimatedParticleSteps=particle_steps,
        nominalPhysicalTimeAggregate=t_tg+sound_reps*t_sound+t_msd,
    ))
with out.open('w',newline='') as f:
    w=csv.DictWriter(f,fieldnames=list(rows[0])); w.writeheader(); w.writerows(rows)
print(f'[0493x13a] manifest={out}')
PY_MANIFEST

if [[ "$ANALYZE_ONLY" == 1 ]]; then
  python3 scripts/analyze_0493x13a_src_high_re_presweep.py --root "$SWEEP_ROOT"
  exit 0
fi

# Read canonical per-case values from the manifest so the manifest is the one definition of the matrix.
read_case_manifest() {
  python3 - "$manifest" "$1" <<'PY_READ'
import csv,sys
with open(sys.argv[1],newline='') as f:
    for r in csv.DictReader(f):
        if r['case']==sys.argv[2]:
            for k in ('rotationAngleRad','dt','Lx','Ly','tgSteps','soundSteps','msdSteps','targetLambdaMeanOverCell'):
                print(r[k])
            raise SystemExit(0)
raise SystemExit(2)
PY_READ
}

for label in A0 A1 A2 A3 A4 A5 A6; do
  contains_case "$label" || continue
  mapfile -t V < <(read_case_manifest "$label")
  angle_rad="${V[0]}"; dt="${V[1]}"; lx="${V[2]}"; ly="${V[3]}"
  tg_steps="${V[4]}"; sound_steps="${V[5]}"; msd_steps="${V[6]}"; lam="${V[7]}"

  angle_deg=$(python3 -c "import math; print(float('$angle_rad')*180/math.pi)")
  echo "===== 0493x13a case=$label gamma=$GAMMA angle=${angle_deg}deg lambda/h=$lam dt=$dt ====="
  env \
    RUN_ROOT="$SWEEP_ROOT/$label" CLEAN_RUN_ROOT=1 PREFLIGHT_ONLY="$PREFLIGHT_ONLY" \
    LIVE_PROGRESS="$LIVE_PROGRESS" THREADS="$THREADS" \
    Lx="$lx" Ly="$ly" NX="$CAL_NX" NY="$CAL_NY" GAMMA="$GAMMA" \
    DT="$dt" KBT="$KBT" PARTICLE_MASS="$PARTICLE_MASS" SEED="$SEED" \
    ROTATION_ANGLE="$angle_rad" RANDOM_ROTATION_SIGN=true GRID_SHIFT_ENABLE=true \
    THERMOSTAT_ENABLE="$THERMOSTAT_ENABLE" THERMOSTAT_MODE="$THERMOSTAT_MODE" \
    THERMOSTAT_EVERY="$THERMOSTAT_EVERY" THERMOSTAT_TARGET_KBT="$KBT" \
    THERMOSTAT_MIN_PARTICLES="$THERMOSTAT_MIN_PARTICLES" \
    TG_MODE_X=1 TG_MODE_Y=1 TG_STEPS="$tg_steps" TG_DUMP_COUNT="$TG_DUMP_COUNT" \
    SOUND_MODE_X="$SOUND_MODE_X" SOUND_DENSITY_AMPLITUDE="$SOUND_DENSITY_AMPLITUDE" \
    SOUND_STEPS="$sound_steps" SOUND_DUMP_COUNT="$SOUND_DUMP_COUNT" \
    SOUND_REPLICATES="$SOUND_REPLICATES" \
    MSD_GRID_MODE=cell_equivalent MSD_MAX_NX="$CAL_NX" MSD_MAX_NY="$CAL_NY" \
    MSD_STEPS="$msd_steps" MSD_DUMP_COUNT="$MSD_DUMP_COUNT" \
    MSD_SAMPLE_PARTICLES="$MSD_SAMPLE_PARTICLES" \
    CHARACTERISTIC_U="$CHARACTERISTIC_U" CHARACTERISTIC_L="$CHARACTERISTIC_L" \
    bash scripts/run_0493w1_src_fluid_calibrator.sh
 done

if [[ "$PREFLIGHT_ONLY" == 1 ]]; then
  echo "[0493x13a] PREFLIGHT_ONLY=1 requestedCases=$CASES"
  exit 0
fi

python3 scripts/analyze_0493x13a_src_high_re_presweep.py --root "$SWEEP_ROOT"
