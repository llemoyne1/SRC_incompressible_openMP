#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

PARENT="scripts/run_0493x10o_q6_thermal_interface_static_drop.sh"
ANALYZER="scripts/analyze_0493x12yl_young_laplace_calibrator.py"
[[ -f "$PARENT" ]] || { echo "[0493x12yl] ERROR missing $PARENT" >&2; exit 2; }
[[ -f "$ANALYZER" ]] || { echo "[0493x12yl] ERROR missing $ANALYZER" >&2; exit 2; }
[[ -f src/cuda_q6_resident_0400.cu ]] || { echo "[0493x12yl] ERROR missing src/cuda_q6_resident_0400.cu" >&2; exit 2; }

# Exact current production-interface prerequisites.  The calibrator itself does
# not modify C++/CUDA; it only selects already existing runtime paths.
for marker in \
  'MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE_SWAP' \
  'MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE' \
  'MPCD_X10_KINETIC_INTERFACE_QUADRATIC' \
  'MPCD_X10_KINETIC_INTERFACE_CIC' \
  'MPCD_X12A_LOCAL_THERMAL_COOLING'; do
  grep -q "$marker" src/cuda_q6_resident_0400.cu || {
    echo "[0493x12yl] ERROR current source missing production marker: $marker" >&2
    exit 2
  }
done

PROFILE="${PROFILE:-production}"
case "$PROFILE" in
  quick)
    RADII="${RADII:-32 40}"
    REPLICATES="${REPLICATES:-1}"
    STEPS="${STEPS:-500}"
    ;;
  production)
    RADII="${RADII:-32 40 48}"
    REPLICATES="${REPLICATES:-3}"
    STEPS="${STEPS:-1000}"
    ;;
  *)
    echo "[0493x12yl] ERROR PROFILE must be quick or production" >&2
    exit 2
    ;;
esac

RUN_ROOT="${RUN_ROOT:-runs/0493x12yl_young_laplace}"
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
ANALYZE_ONLY="${ANALYZE_ONLY:-0}"
TAIL_START="${TAIL_START:-0.5}"

NX="${NX:-256}"
NY="${NY:-256}"
Lx="${Lx:-1.0}"
Ly="${Ly:-1.0}"
GAMMA="${GAMMA:-20}"
DT="${DT:-0.002}"
KBT="${KBT:-0.125}"
LIQUID_MASS="${LIQUID_MASS:-1.0}"
SIGMA_DECLARED="${SIGMA_DECLARED:-945}"
SURFACE_TENSION_MIN_RADIUS_CELLS="${SURFACE_TENSION_MIN_RADIUS_CELLS:-4}"
MPCD_X12A_LOCAL_THERMAL_RADIUS_CELLS="${MPCD_X12A_LOCAL_THERMAL_RADIUS_CELLS:-25.298221281347036}"
ALLOW_LOCAL_COOLING="${ALLOW_LOCAL_COOLING:-0}"

BASE_SEED="${BASE_SEED:-4931301}"
SEED_STRIDE="${SEED_STRIDE:-1009}"
SUMMARY_EVERY="${SUMMARY_EVERY:-10}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-0}"
THREADS="${THREADS:-8}"

# Visual inspection remains available during the campaign and does not block
# between paired cases.  Recording is cheap here because static drops contain
# only the liquid particles and the default cadence is sparse.
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-1}"
LIVE_VIS_RECORD_ENABLE="${LIVE_VIS_RECORD_ENABLE:-1}"
LIVE_VIS_RECORD_EVERY="${LIVE_VIS_RECORD_EVERY:-100}"
LIVE_VIS_RECORD_FIELDS="${LIVE_VIS_RECORD_FIELDS:-mass}"
LIVE_VIS_HOLD_ON_EXIT=0
FILTER_SAMPLE_EVERY="${FILTER_SAMPLE_EVERY:-100}"
FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-1}"

CHARACTERISTIC_U="${CHARACTERISTIC_U:--1}"
CHARACTERISTIC_D="${CHARACTERISTIC_D:--1}"
KINEMATIC_VISCOSITY="${KINEMATIC_VISCOSITY:--1}"
GRAVITY_MAGNITUDE="${GRAVITY_MAGNITUDE:-0}"

export OMP_NUM_THREADS="$THREADS"
export LIVE_PROGRESS LIVE_VIS_ENABLE LIVE_VIS_EVERY LIVE_VIS_RECORD_ENABLE
export LIVE_VIS_RECORD_EVERY LIVE_VIS_RECORD_FIELDS LIVE_VIS_HOLD_ON_EXIT
export FILTER_SAMPLE_EVERY FILTERED_RECORDING_ENABLE

# Lock the current production kinetic free-surface chain.
export MPCD_X10J_SIMPLE_SPECULAR_ABLATION=0
export MPCD_X10K_LOCAL_FRAME_SPECULAR_ABLATION=0
export MPCD_X10M_MOVING_INTERFACE_WALL=0
export MPCD_X10N_Q6_CONTINUOUS_INTERFACE_WALL=0
export MPCD_X10O_Q6_THERMAL_INTERFACE_WALL=1
export MPCD_X10L_PREWALL_INTERFACE_DIAGNOSTICS=0
export MPCD_X10_KINETIC_INTERFACE_CIC=1
export MPCD_X10_KINETIC_INTERFACE_QUADRATIC=1
export MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE=1
export MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE_SWAP=1
export MPCD_X10P_INITIAL_OVERLAP_RESOLUTION=1
export MPCD_X10R_Q6_THERMAL_FULL_VECTOR_ENDPOINT_VELOCITY=0
export MPCD_X10S_Q6_THERMAL_SEGMENT_NORMAL_KINEMATICS=0
export MPCD_X10T_Q6_THERMAL_RIGID_TANGENTIAL_KINEMATICS=0
export MPCD_X10_KINETIC_INTERFACE_THERMAL_PHASE_LIMITER=0
export MPCD_X12A_LOCAL_THERMAL_COOLING=1
export MPCD_X12A_LOCAL_THERMAL_RADIUS_CELLS

export MPCD_X10O_THERMAL_PARTICLE_MASS="$LIQUID_MASS"
export MPCD_X10O_THERMAL_SIGMAS="${MPCD_X10O_THERMAL_SIGMAS:-3.0}"
export MPCD_X10O_THERMAL_MAX_CELLS="${MPCD_X10O_THERMAL_MAX_CELLS:-0.75}"

# Use the Q6-G-F production path; no resampling or virial kick.
export RUN_MODE=src-q6-g-f
export SPECIES_RESAMPLING_ENABLE=false
export LIQUID_RESAMPLING_ENABLE=false
export GAS_RESAMPLING_ENABLE=false
export WEIGHTED_RESAMPLING_ENABLE_OVERRIDE=false
export CUDA_EMPTY_REFILL_ENABLE_OVERRIDE=false
export VIRIAL_DENSITY_KICK_ENABLE=false

read -r H CX CY RHO_REF <<<"$(python3 - \
  "$Lx" "$Ly" "$NX" "$NY" "$GAMMA" "$LIQUID_MASS" <<'PY'
import sys
lx,ly=float(sys.argv[1]),float(sys.argv[2]); nx,ny=int(sys.argv[3]),int(sys.argv[4])
gamma,mass=float(sys.argv[5]),float(sys.argv[6])
dx,dy=lx/nx,ly/ny
if abs(dx-dy)>1e-12*max(1.0,abs(dx),abs(dy)):
    raise SystemExit('[0493x12yl] square cells required')
if min(lx,ly,nx,ny,gamma,mass)<=0:
    raise SystemExit('[0493x12yl] invalid geometry/density')
print(f'{dx:.17g} {0.5*lx:.17g} {0.5*ly:.17g} {gamma*mass/(dx*dy):.17g}')
PY
)"

python3 - \
  "$PROFILE" "$Lx" "$Ly" "$NX" "$NY" "$H" "$GAMMA" "$DT" "$KBT" "$LIQUID_MASS" \
  "$SIGMA_DECLARED" "$RADII" "$REPLICATES" "$STEPS" "$SUMMARY_EVERY" \
  "$SURFACE_TENSION_MIN_RADIUS_CELLS" "$MPCD_X12A_LOCAL_THERMAL_RADIUS_CELLS" "$ALLOW_LOCAL_COOLING" \
  "$LIVE_VIS_RECORD_ENABLE" "$LIVE_VIS_RECORD_EVERY" <<'PY_PREFLIGHT'
import math,sys
(profile,lx,ly,nx,ny,h,gamma,dt,kbt,mass,sigma,radii,reps,steps,summary,rmin,rcool,allow_cool,rec_en,rec_every)=sys.argv[1:]
lx,ly,h,dt,kbt,mass,sigma,rmin,rcool=map(float,(lx,ly,h,dt,kbt,mass,sigma,rmin,rcool))
nx,ny,gamma,reps,steps,summary=int(nx),int(ny),int(gamma),int(reps),int(steps),int(summary)
allow_cool=int(allow_cool); rec_every=int(rec_every)
radii=[float(x) for x in radii.split()]
if not radii or reps<1 or steps<1 or summary<1 or sigma<=0:
    raise SystemExit('[0493x12yl] invalid campaign inputs')
if any(r<=0 for r in radii):
    raise SystemExit('[0493x12yl] radii must be positive')
if any(r*h >= 0.5*min(lx,ly)-8*h for r in radii):
    raise SystemExit('[0493x12yl] each drop must stay at least 8 cells from domain walls')
if min(radii) <= rcool + 2.0 and not allow_cool:
    raise SystemExit(
        f'[0493x12yl] smallest R/h={min(radii):g} is too close to x12a Rc/h={rcool:g}; '
        'use resolved radii or set ALLOW_LOCAL_COOLING=1 intentionally')
if min(radii) <= 2.0*rmin:
    raise SystemExit('[0493x12yl] radii too close to curvature cutoff; resolved calibration required')
rho=gamma*mass/h**2
pairs=len(radii)*reps
runs=2*pairs
particle_steps=0.0
for r in radii:
    np_est=math.pi*r*r*gamma
    particle_steps += 2*reps*steps*np_est
frames=1+steps//max(1,rec_every)
rec_gb=(runs*frames*nx*ny*4)/1e9 if str(rec_en).lower() in ('1','true','yes','on') else 0.0
print('===== 0493x12yl YOUNG-LAPLACE CALIBRATOR PREFLIGHT =====')
print(f'profile={profile} path=src-q6-g-f chain=x10o+CIC+Q2+x10u+x10v+x12a')
print(f'grid={nx}x{ny} L=({lx:.9g},{ly:.9g}) h={h:.9g} gamma={gamma} rhoRef={rho:.9g}')
print(f'fluid dt={dt:.9g} kBT={kbt:.9g} mass={mass:.9g}')
print(f'sigmaDeclared={sigma:.9g} radiiCells={radii} replicates={reps} steps={steps} summaryEvery={summary}')
print(f'curvatureCutoffMinRadiusCells={rmin:g} x12aRcCells={rcool:g} localCoolingExpected=inactive')
print(f'pairedRuns={pairs} totalSolverRuns={runs} estimatedParticleSteps={particle_steps:.6g}')
print(f'livevis=enabled-by-caller recordingEstimated={rec_gb:.3f}GB')
print('observable=paired solved-Q6 pressure increment: dp_cap=p(sigma)-p(0)')
print('law=dp_cap=sigma_eff*<kappa>_active; sigma_eff is mechanical/static surface tension')
print('note=capillary-wave dispersion is intentionally NOT folded into this scalar calibration')
PY_PREFLIGHT

if [[ "$PREFLIGHT_ONLY" == 1 ]]; then
  echo "[0493x12yl] PREFLIGHT_ONLY=1; no simulation launched"
  exit 0
fi

MANIFEST="$RUN_ROOT/manifest_0493x12yl.csv"
if [[ "$ANALYZE_ONLY" != 1 ]]; then
  [[ "$CLEAN_RUN_ROOT" == 1 ]] && rm -rf "$RUN_ROOT"
  mkdir -p "$RUN_ROOT/logs" "$RUN_ROOT/analysis"
  echo 'case,role,sigma,sigma_declared,r_cells,seed,run_dir,h,gamma,liquid_mass,steps,min_radius_cells,x12a_radius_cells,chain' > "$MANIFEST"
else
  [[ -s "$MANIFEST" ]] || { echo "[0493x12yl] ERROR ANALYZE_ONLY manifest missing: $MANIFEST" >&2; exit 2; }
fi

run_one() {
  local role="$1" sigma="$2" rc="$3" rep="$4" seed="$5"
  local sigma_tag="${sigma//./p}"; sigma_tag="${sigma_tag//-/m}"
  local tag="${role}_s${sigma_tag}_r${rc}_rep${rep}_seed${seed}"
  local dir="$RUN_ROOT/$tag"
  local log="$RUN_ROOT/logs/${tag}.log"

  echo
  echo "===== 0493x12yl $tag ====="
  echo "[0493x12yl] role=$role sigma=$sigma R/h=$rc rep=$rep seed=$seed"

  if [[ "$role" == baseline ]]; then
    export MPCD_X11C_FORCE_X9E_SIGMA0=1
  else
    export MPCD_X11C_FORCE_X9E_SIGMA0=0
  fi

  RUN_ROOT="$dir" \
  NX="$NX" NY="$NY" Lx="$Lx" Ly="$Ly" \
  GAMMA="$GAMMA" DT="$DT" KBT="$KBT" LIQUID_MASS="$LIQUID_MASS" \
  SIGMA_ACTIVE="$sigma" SURFACE_TENSION_MIN_RADIUS_CELLS="$SURFACE_TENSION_MIN_RADIUS_CELLS" \
  DROP_RADIUS_CELLS="$rc" DROP_CENTER_X="$CX" DROP_CENTER_Y="$CY" \
  DROP_VX=0 DROP_VY=0 GRAVITY_Y=0 CONTACT_ANGLE_DEG=-1 \
  SEED="$seed" STEPS="$STEPS" SUMMARY_EVERY="$SUMMARY_EVERY" \
  DUMP_STATE_EVERY="$DUMP_STATE_EVERY" INACTIVE_SLOTS=0 CLEAN_RUN_ROOT=1 \
  OVERWRITE_LIVEVIS_CONTROL=1 \
  bash "$PARENT" 2>&1 | tee "$log"

  local pressure="$dir/output/cuda_static_drop_pressure_0493x9e.csv"
  [[ -s "$pressure" ]] || { echo "[0493x12yl] ERROR missing pressure CSV: $pressure" >&2; exit 2; }
  echo "$tag,$role,$sigma,$SIGMA_DECLARED,$rc,$seed,$dir,$H,$GAMMA,$LIQUID_MASS,$STEPS,$SURFACE_TENSION_MIN_RADIUS_CELLS,$MPCD_X12A_LOCAL_THERMAL_RADIUS_CELLS,x10o+CIC+Q2+x10u+x10v+x12a" >> "$MANIFEST"
}

if [[ "$ANALYZE_ONLY" != 1 ]]; then
  for ((rep=0; rep<REPLICATES; ++rep)); do
    seed=$((BASE_SEED + rep * SEED_STRIDE))
    for rc in $RADII; do
      # Pair baseline and active run immediately at identical (R/h, seed).
      run_one baseline 0 "$rc" "$rep" "$seed"
      run_one active "$SIGMA_DECLARED" "$rc" "$rep" "$seed"
    done
  done
fi

python3 "$ANALYZER" \
  --manifest "$MANIFEST" \
  --output-dir "$RUN_ROOT/analysis" \
  --tail-start "$TAIL_START" \
  --characteristic-U "$CHARACTERISTIC_U" \
  --characteristic-D "$CHARACTERISTIC_D" \
  --kinematic-viscosity "$KINEMATIC_VISCOSITY" \
  --gravity "$GRAVITY_MAGNITUDE"

echo "[0493x12yl] COMPLETE result=$RUN_ROOT/analysis/young_laplace_calibration_0493x12yl.csv"
