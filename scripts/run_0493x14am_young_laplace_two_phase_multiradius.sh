#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
SEED="${SEED:-4931901}"
source "$ROOT/scripts/src_mpcd_run_ok_common.sh"
suite_root_cd_0434

# 0493x14am — two-phase Young-Laplace multi-radius calibration.
# Tooling only: no C++/CUDA change and no new runtime diagnostic.
# Existing x9e measures pL(Q6 gauge)-pG(x6g EOS gauge) and curvature in-run.

GENERATOR="$ROOT/scripts/generate_0493x14j_drop_two_temperature.py"
ANALYZER="$ROOT/scripts/analyze_0493x14am_young_laplace_two_phase.py"
SRC="$ROOT/src/cuda_q6_resident_0400.cu"
for f in "$GENERATOR" "$ANALYZER" "$SRC"; do
  [[ -f "$f" ]] || { echo "[0493x14am] ERROR missing $f" >&2; exit 2; }
done
for marker in \
  'cuda_static_drop_pressure_0493x9e.csv' \
  'eos_accessible_volume' \
  '0493x14v-gas-kinetic-excess' \
  '0493x14ad — local-x6g-face gauge sampling with residual resultant projection' \
  '0493x14ai — production-candidate device-side Q6 resultant closure' \
  'B1-exact-post-periodic-device-target'; do
  grep -q "$marker" "$SRC" || { echo "[0493x14am] ERROR source marker missing: $marker" >&2; exit 2; }
done

# -----------------------------------------------------------------------------
# CAMPAIGN PROFILE
# screen (recommended first): 4 radii x 1 seed = 4 runs.
# production:                4 radii x 3 seeds = 12 runs, only if screen ambiguous.
# -----------------------------------------------------------------------------
PROFILE="${PROFILE:-screen}"
case "$PROFILE" in
  screen)
    RADII="${RADII:-32 40 48 64}"
    REPLICATES="${REPLICATES:-1}"
    STEPS="${STEPS:-1000}"
    ;;
  production)
    RADII="${RADII:-32 40 48 64}"
    REPLICATES="${REPLICATES:-3}"
    STEPS="${STEPS:-1000}"
    ;;
  *) echo '[0493x14am] ERROR PROFILE must be screen or production' >&2; exit 2 ;;
esac

# -----------------------------------------------------------------------------
# PHYSICAL/NUMERICAL POINT — historical x13h liquid + explicit x14 gas.
# Visible here intentionally.
# -----------------------------------------------------------------------------
Lx="${Lx:-1.0}"; Ly="${Ly:-1.0}"; NX="${NX:-256}"; NY="${NY:-256}"
GAMMA="${GAMMA:-20}"
DT="${DT:-0.002}"
LIQUID_TYPE="${LIQUID_TYPE:-1}"; GAS_TYPE="${GAS_TYPE:-2}"
LIQUID_MASS="${LIQUID_MASS:-1.0}"; GAS_MASS="${GAS_MASS:-0.1}"
LIQUID_KBT="${LIQUID_KBT:-0.02}"; GAS_KBT="${GAS_KBT:-0.08}"
# IMPORTANT: x6g EOS reads params.kBT (global), so global KBT belongs to gas.
# x10o resolves the liquid species thermostat target under bilateral x14k.
KBT="${KBT:-$GAS_KBT}"
THERMOSTAT_TARGET_KBT="${THERMOSTAT_TARGET_KBT:-$GAS_KBT}"
THERMOSTAT_ENABLE="${THERMOSTAT_ENABLE:-true}"
THERMOSTAT_MODE="${THERMOSTAT_MODE:-cell_relative_rescale}"
THERMOSTAT_EVERY="${THERMOSTAT_EVERY:-1}"
THERMOSTAT_MIN_PARTICLES="${THERMOSTAT_MIN_PARTICLES:-3}"
ROTATION_ANGLE="${ROTATION_ANGLE:-1.5707963267948966}" # 90 deg
RANDOM_ROTATION_SIGN="${RANDOM_ROTATION_SIGN:-true}"
GRID_SHIFT_ENABLE="${GRID_SHIFT_ENABLE:-true}"

SURFACE_TENSION_SIGMA="${SURFACE_TENSION_SIGMA:-2560.0}"
SURFACE_TENSION_MIN_RADIUS_CELLS="${SURFACE_TENSION_MIN_RADIUS_CELLS:-4}"
CENTER_X="${CENTER_X:-0.5}"; CENTER_Y="${CENTER_Y:-0.5}"
PHASE_INTERFACE_KINETIC_REFLECTION_FRACTION="${PHASE_INTERFACE_KINETIC_REFLECTION_FRACTION:-1.0}"
PHASE_INTERFACE_EVAPORATION_TARGET_TYPE="${PHASE_INTERFACE_EVAPORATION_TARGET_TYPE:--1}"
PHASE_INTERFACE_CONTACT_ANGLE_DEG="${PHASE_INTERFACE_CONTACT_ANGLE_DEG:--1}"
X10O_THERMAL_SIGMAS="${X10O_THERMAL_SIGMAS:-3.0}"
X10O_THERMAL_MAX_CELLS="${X10O_THERMAL_MAX_CELLS:-0.75}"
X12A_LOCAL_THERMAL_RADIUS_CELLS="${X12A_LOCAL_THERMAL_RADIUS_CELLS:-25.298221281347036}"

LIQUID_Q6_STRENGTH="${LIQUID_Q6_STRENGTH:-1.0}"; GAS_Q6_STRENGTH="${GAS_Q6_STRENGTH:-0.0}"
SPECIES_Q6_MIN_FILL_FRACTION="${SPECIES_Q6_MIN_FILL_FRACTION:-0.10}"
Q6_GF_DENSITY_RELAXATION_TIME="${Q6_GF_DENSITY_RELAXATION_TIME:-0.25}"
Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE="${Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE:-1}"
Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES="${Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES:-3.0}"
Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES="${Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES:-6.0}"
Q6_GF_DENSITY_TRACTION_GAIN="${Q6_GF_DENSITY_TRACTION_GAIN:-1.0}"

CASE_LABEL="0493x14am_young_laplace_two_phase_multiradius"
RUN_MODE="src-q6-g-f"; TOPOLOGY="periodic"
PROJECTION_BACKEND="${PROJECTION_BACKEND:-cuda}"
PROJECTION_OPERATOR="${PROJECTION_OPERATOR:-auto_fv_cg}"
PROJECTION_MAX_ITERATIONS="${PROJECTION_MAX_ITERATIONS:-2000}"
PROJECTION_TOLERANCE="${PROJECTION_TOLERANCE:-1.0e-5}"
PROJECTION_MOMENTUM_CORRECTION_ENABLE=false
Q6_PROJECTION_STRENGTH=1.0; Q6_STRICT=1
Q6_FORCE_PROJECTION_MODE=prestream_single_fused
Q6_GF_EXTERNAL_SPECIES=1; Q6_GF_HAS_GAS_PHASE=1
Q6_GF_MIN_FILL_FRACTION="$SPECIES_Q6_MIN_FILL_FRACTION"
SPECIES_RESAMPLING_ENABLE=false; LIQUID_RESAMPLING_ENABLE=false; GAS_RESAMPLING_ENABLE=false
VIRIAL_DENSITY_KICK_ENABLE=false; WEIGHTED_RESAMPLING_ENABLE_OVERRIDE=false
CUDA_EMPTY_REFILL_ENABLE_OVERRIDE=false

BASE_SEED="${BASE_SEED:-4931901}"; SEED_STRIDE="${SEED_STRIDE:-1009}"
SUMMARY_EVERY="${SUMMARY_EVERY:-10}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-1000}"
TAIL_START="${TAIL_START:-0.5}"
CLEAN_CAMPAIGN_ROOT="${CLEAN_CAMPAIGN_ROOT:-1}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
ANALYZE_ONLY="${ANALYZE_ONLY:-0}"
AUTO_BUILD="${AUTO_BUILD:-0}"; BUILD_IF_STALE="${BUILD_IF_STALE:-0}"
BIN="${BIN:-${SRC_MPCD_DEFAULT_BIN_0434:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}}"
CAMPAIGN_ROOT="${CAMPAIGN_ROOT:-runs/0493x14am_young_laplace_two_phase_resolved_gas_s2560}"

# LiveVis is active, but recording is deliberately sparse and reduced-grid.
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"; LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-mass}"
LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-1}"; LIVE_VIS_NX="${LIVE_VIS_NX:-128}"; LIVE_VIS_NY="${LIVE_VIS_NY:-128}"
LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-0}"
LIVE_VIS_RECORD_ENABLE="${LIVE_VIS_RECORD_ENABLE:-1}"
LIVE_VIS_RECORD_EVERY="${LIVE_VIS_RECORD_EVERY:-100}"
LIVE_VIS_RECORD_FIELDS="${LIVE_VIS_RECORD_FIELDS:-mass}"
FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-1}"
FILTER_SAMPLE_EVERY="${FILTER_SAMPLE_EVERY:-100}"
PARTICLE_TYPE_FILTER="$LIQUID_TYPE"
RECORD_ENABLE=true; RECORD_EVERY="$LIVE_VIS_RECORD_EVERY"; RECORD_FIELDS="$LIVE_VIS_RECORD_FIELDS"; FILTER_MODE=none

# Common machinery variables.
GEN_CASE=tg; U0=0.0; VELOCITY_MODE=zero; PARTICLE_MASS="$GAS_MASS"
BACKGROUND_TYPE="$GAS_TYPE"; INACTIVE_TYPE="$GAS_TYPE"; TG_HOLE_ENABLE=false
SPECIES_RESIDENT_MODE=off; RESAMPLING_HOST_PATCHBACK_ENABLE=0; MASS_RECONDITION_ENABLE=0
RESAMPLING_THERMAL_RENORMALIZATION_ENABLE=false; RESAMPLING_MASS_GUARD_ENABLE=false
RUN_OK_REFERENCE_PARTICLE_MASS="$LIQUID_MASS"; RUN_OK_GENERATOR_PATH="$GENERATOR"
export RUN_OK_REFERENCE_PARTICLE_MASS RUN_OK_GENERATOR_PATH
PHASE_INTERFACE_A_SELECTOR="type:${LIQUID_TYPE}"; PHASE_INTERFACE_B_SELECTOR="type:${GAS_TYPE}"

suite_defaults_common_0434
suite_compute_derived_0434

read -r H AREA RHO_L RHO_G P_REF <<<"$(python3 - "$Lx" "$Ly" "$NX" "$NY" "$GAMMA" "$LIQUID_MASS" "$GAS_MASS" "$GAS_KBT" <<'PY'
import math,sys
lx,ly=float(sys.argv[1]),float(sys.argv[2]); nx,ny=int(sys.argv[3]),int(sys.argv[4])
g,mL,mG,kG=map(float,sys.argv[5:9])
hx,hy=lx/nx,ly/ny
if abs(hx-hy)>1e-12*max(1.0,abs(hx),abs(hy)): raise SystemExit('[0493x14am] square cells required')
if abs(hx-1/256)>1e-12: raise SystemExit(f'[0493x14am] require h=1/256, got {hx:.17g}')
if int(g)!=20: raise SystemExit('[0493x14am] resolved liquid/gas point requires gamma=20')
A=hx*hy; rhoL=g*mL/A; rhoG=g*mG/A; pref=g*kG/A
print(f'{hx:.17g} {A:.17g} {rhoL:.17g} {rhoG:.17g} {pref:.17g}')
PY
)"

python3 - "$PROFILE" "$RADII" "$REPLICATES" "$STEPS" "$H" "$Lx" "$Ly" "$CENTER_X" "$CENTER_Y" \
 "$X12A_LOCAL_THERMAL_RADIUS_CELLS" "$SURFACE_TENSION_MIN_RADIUS_CELLS" "$SURFACE_TENSION_SIGMA" "$P_REF" \
 "$KBT" "$GAS_KBT" "$LIQUID_KBT" "$DT" "$ROTATION_ANGLE" <<'PY'
import math,sys
(profile,radii,reps,steps,h,lx,ly,cx,cy,rcool,rmin,sigma,pref,kglob,kg,kl,dt,ang)=sys.argv[1:]
radii=[float(x) for x in radii.split()]; reps=int(reps); steps=int(steps)
h,lx,ly,cx,cy,rcool,rmin,sigma,pref,kglob,kg,kl,dt,ang=map(float,(h,lx,ly,cx,cy,rcool,rmin,sigma,pref,kglob,kg,kl,dt,ang))
if len(radii)<3: raise SystemExit('[0493x14am] need at least 3 radii for a slope')
if reps<1 or steps<100: raise SystemExit('[0493x14am] invalid repeats/steps')
if abs(kglob-kg)>1e-14: raise SystemExit('[0493x14am] global KBT must equal GAS_KBT because x6g EOS reads params.kBT')
if abs(kl-.02)>1e-14 or abs(dt-.002)>1e-15 or abs(ang-math.pi/2)>1e-12:
    raise SystemExit('[0493x14am] resolved liquid/gas qualification point mismatch')
if min(radii) <= rcool+2: raise SystemExit('[0493x14am] smallest radius too close to x12a radius')
if min(radii) <= 2*rmin: raise SystemExit('[0493x14am] smallest radius too close to curvature cutoff')
for r in radii:
    if r*h >= min(cx,lx-cx,cy,ly-cy)-16*h: raise SystemExit(f'[0493x14am] R/h={r:g} lacks 16h periodic clearance')
print('===== 0493x14am TWO-PHASE YOUNG-LAPLACE PREFLIGHT =====')
print(f'profile={profile} radiiCells={radii} replicates={reps} totalRuns={len(radii)*reps}')
print(f'grid=256x256 L=1x1 h={h:.12g} gamma=20 dt={dt:.17g} angle=90deg')
print(f'liquid: m=1 kBT={kl:.9g}; gas: m=0.1 kBT={kg:.9g}; globalKBT(EOS)={kglob:.9g}')
print(f'sigma={sigma:.9g} gasReferencePressure={pref:.9g} cutoffRmin/h={rmin:g} x12aRc/h={rcool:g}')
for r in radii:
    R=r*h
    print(f'  R/h={r:5g} R={R:.9g} kappa=1/R={1/R:.9g} LaplaceTarget=sigma/R={sigma/R:.9g}')
print(f'steps/run={steps}; x9e summary cadence is runner SUMMARY_EVERY; tail fraction analyzed later')
print('observable: measuredPressureJump = pL_Q6_gauge - pG_x6g_EOS_gauge (existing x9e)')
print('fit: dp = intercept + sigma_eff * <kappa_p3>_tail; 1/Reff is independent cross-check')
print('no sigma=0 baseline; no source modification; no new runtime diagnostic')
PY

if suite_truthy_0434 "$PREFLIGHT_ONLY"; then
  echo '[0493x14am] PREFLIGHT_ONLY=1; no simulation launched'
  exit 0
fi

MANIFEST="$CAMPAIGN_ROOT/manifest_0493x14am.csv"
if ! suite_truthy_0434 "$ANALYZE_ONLY"; then
  if suite_truthy_0434 "$CLEAN_CAMPAIGN_ROOT"; then rm -rf "$CAMPAIGN_ROOT"; fi
  mkdir -p "$CAMPAIGN_ROOT/logs" "$CAMPAIGN_ROOT/analysis"
  echo 'radius_cells,replicate,seed,run_dir,sigma' > "$MANIFEST"
else
  [[ -s "$MANIFEST" ]] || { echo "[0493x14am] ERROR missing manifest: $MANIFEST" >&2; exit 2; }
fi

run_one() {
  local rc="$1" rep="$2" seed="$3"
  local tag="r${rc}_rep${rep}_seed${seed}"
  local RUN_ROOT="$CAMPAIGN_ROOT/$tag"
  local CASE_LABEL="0493x14am_${tag}"
  local STATE="$RUN_ROOT/init/${CASE_LABEL}.smpcd"
  local OUT="$RUN_ROOT/output"
  local PARAMS="$RUN_ROOT/params/${CASE_LABEL}.kv"
  local LOG="$RUN_ROOT/logs/${CASE_LABEL}.log"
  local TF="$RUN_ROOT/logs/${CASE_LABEL}.time"
  local RADIUS
  RADIUS="$(awk -v r="$rc" -v h="$H" 'BEGIN{printf "%.17g",r*h}')"

  echo
  echo "===== 0493x14am TWO-PHASE YL R/h=$rc rep=$rep seed=$seed ====="
  echo "PATHS: state=$STATE params=$PARAMS output=$OUT"
  echo "PHYS:  gamma=$GAMMA angle=90deg dt=$DT kBT_L=$LIQUID_KBT kBT_G=$GAS_KBT globalKBT(EOS)=$KBT"
  echo "CAP:   sigma=$SURFACE_TENSION_SIGMA R/h=$rc target=$(awk -v s="$SURFACE_TENSION_SIGMA" -v r="$RADIUS" 'BEGIN{printf "%.9g",s/r}')"
  echo "CHAIN: x6g accessible-volume + x9 + x14l+x14v+x14ad+x14ai-fix1 + liquid x10o/CIC/Q2/x10p/q/x10u/x10v/x12a"

  CLEAN_RUN_ROOT=1
  suite_prepare_dirs_0434 "$RUN_ROOT"
  python3 "$GENERATOR" \
    --output "$STATE" --Lx "$Lx" --Ly "$Ly" --nx "$NX" --ny "$NY" --gamma "$GAMMA" \
    --center-x "$CENTER_X" --center-y "$CENTER_Y" --radius "$RADIUS" \
    --liquid-type "$LIQUID_TYPE" --gas-type "$GAS_TYPE" \
    --liquid-mass "$LIQUID_MASS" --gas-mass "$GAS_MASS" \
    --liquid-kBT "$LIQUID_KBT" --gas-kBT "$GAS_KBT" --seed "$seed"

  local LREF GREF
  LREF="$(awk -v g="$GAMMA" -v m="$LIQUID_MASS" 'BEGIN{printf "%.17g",g*m}')"
  GREF="$(awk -v g="$GAMMA" -v m="$GAS_MASS" 'BEGIN{printf "%.17g",g*m}')"
  cat > "$PARAMS" <<PARAMS
inputState = $STATE
outputDir = $OUT
Lx = $Lx
Ly = $Ly
Nx = $NX
Ny = $NY
dt = $DT
nSteps = $STEPS
bcLeft = periodic
bcRight = periodic
bcBottom = periodic
bcTop = periodic
bcX = periodic
bcY = periodic
openBoundarySegmentsEnable = false
openBoundarySegmentCount = 0
bodyAccelerationX = 0.0
bodyAccelerationY = 0.0
taylorGreenForcingEnable = false
wallVpEnable = false
wallAccommodation = 1.0
wallThermalNoise = 0.0
speciesRegistryEnable = true
speciesCount = 2
species0 = $LIQUID_TYPE incompressible_liquid liquid $LIQUID_Q6_STRENGTH 1.0 $LREF
species0ResamplingEnable = false
species0ThermostatTargetKBT = $LIQUID_KBT
species1 = $GAS_TYPE compressible_gas gas $GAS_Q6_STRENGTH 0.0 $GREF
species1ResamplingEnable = false
species1ThermostatTargetKBT = $GAS_KBT
speciesRequireRegisteredTypes = true
speciesThermostatEnable = true
speciesDiagnosticsEnable = true
speciesDiagnosticsFilename = species_runtime_0493x14am.csv
speciesCellDiagnosticsEnable = false
speciesQ6Sensitivity = 1.0
speciesQ6FallbackMode = common
speciesQ6ComparisonTolerance = 1.0e-11
PARAMS
  suite_write_common_params_0434 "$RUN_MODE" >> "$PARAMS"
  run_ok_surface_append_params_0493x13zi "$PARAMS" "$PHASE_INTERFACE_A_SELECTOR" "$PHASE_INTERFACE_B_SELECTOR"
  cat >> "$PARAMS" <<'PARAMS'
phaseInterfaceKineticBilateralRelocation = true
PARAMS

  suite_export_cuda_flags_0434 "$RUN_MODE" "$TOPOLOGY"
  run_ok_surface_export_off_flags_0493x13zi
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WORKSPACE_DOWNLOAD_0272=1
  export MPCD_Q6_PHASE_GAS_PRESSURE_0493X6G=1
  export MPCD_Q6_PHASE_GAS_PRESSURE_MODE_0493X6G=eos_accessible_volume
  export MPCD_Q6_PHASE_GAS_PRESSURE_CONSTANT_0493X6G=0
  export MPCD_Q6_PHASE_GAS_PRESSURE_REFERENCE_0493X6G="$P_REF"
  export MPCD_Q6_PHASE_GAS_PRESSURE_SCALE_0493X6G=1

  export MPCD_X10J_SIMPLE_SPECULAR_ABLATION=0
  export MPCD_X10K_LOCAL_FRAME_SPECULAR_ABLATION=0
  export MPCD_X10M_MOVING_INTERFACE_WALL=0
  export MPCD_X10N_Q6_CONTINUOUS_INTERFACE_WALL=0
  export MPCD_X10O_Q6_THERMAL_INTERFACE_WALL=1
  export MPCD_X10O_THERMAL_PARTICLE_MASS="$LIQUID_MASS"
  export MPCD_X10O_THERMAL_SIGMAS="$X10O_THERMAL_SIGMAS"
  export MPCD_X10O_THERMAL_MAX_CELLS="$X10O_THERMAL_MAX_CELLS"
  export MPCD_X10_KINETIC_INTERFACE_CIC=1
  export MPCD_X10_KINETIC_INTERFACE_QUADRATIC=1
  export MPCD_X10P_INITIAL_OVERLAP_RESOLUTION=1
  export MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE=1
  export MPCD_X14L_GAS_SPECULAR_REFLECTION=1
  export MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE_SWAP=1
  export MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE_NORMAL_ONLY=0
  export MPCD_X10_KINETIC_INTERFACE_THERMAL_PHASE_LIMITER=0
  export MPCD_X12A_LOCAL_THERMAL_COOLING=1
  export MPCD_X12A_LOCAL_THERMAL_RADIUS_CELLS="$X12A_LOCAL_THERMAL_RADIUS_CELLS"

  export MPCD_X14V_GAS_KINETIC_EXCESS_KICK=1
  export MPCD_X14V_SUBTRACT_X6G_THERMODYNAMIC_TRACTION=1
  export MPCD_X14V_X6G_FACE_THERMO_TRACTION=0
  export MPCD_X14V_X6G_GAUGE_FACE_THERMO_TRACTION=0
  export MPCD_X14V_X6G_GAUGE_RESULTANT_PROJECTION=0
  export MPCD_X14V_X6G_LOCAL_FACE_GAUGE_PROJECTION=1
  export MPCD_X14V_REFERENCE_PRESSURE_GEOMETRIC_CLOSURE=0
  export MPCD_X14V_SCATTER_LOSS_DIAGNOSTIC=0
  export MPCD_X14V_GLOBAL_BALANCE_DIAGNOSTIC=0
  export MPCD_X14V_DEVICE_APPLIED_Q6_RESULTANT_CLOSURE=1

  # Existing diagnostics only.
  export MPCD_Q6_STATIC_DROP_DIAGNOSTICS_0493X9E=1
  export MPCD_Q6_ELLIPSE_DIAGNOSTICS_0493X9F=1
  export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9A=0
  export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9B=0
  export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9C=0

  LIVE_VIS_CONTROL_FILE="$RUN_ROOT/livevis_control_0493x14am.kv"
  export LIVE_VIS_CONTROL_FILE LIVE_VIS_ENABLE LIVE_VIS_FIELD LIVE_VIS_EVERY LIVE_VIS_NX LIVE_VIS_NY LIVE_VIS_HOLD_ON_EXIT
  export LIVE_VIS_RECORD_ENABLE LIVE_VIS_RECORD_EVERY LIVE_VIS_RECORD_FIELDS FILTERED_RECORDING_ENABLE FILTER_SAMPLE_EVERY
  export PARTICLE_TYPE_FILTER RECORD_ENABLE RECORD_EVERY RECORD_FIELDS FILTER_MODE
  OVERWRITE_LIVEVIS_CONTROL=1; export OVERWRITE_LIVEVIS_CONTROL
  suite_prepare_livevis_control_0434 "$RUN_ROOT" "$RUN_MODE"
  suite_export_livevis_0434
  suite_write_env_file_0434 "$RUN_ROOT/logs/environment_0493x14am.env" "$RUN_MODE"
  cat >> "$RUN_ROOT/logs/environment_0493x14am.env" <<META
BENCHMARK=0493x14am_two_phase_young_laplace_multiradius
PROFILE=$PROFILE
RADIUS_CELLS=$rc
SIGMA=$SURFACE_TENSION_SIGMA
LIQUID_KBT=$LIQUID_KBT
GAS_KBT=$GAS_KBT
GLOBAL_KBT_X6G_EOS=$KBT
GAS_PRESSURE_REFERENCE=$P_REF
META

  suite_run_binary_0434 "$PARAMS" "$LOG" "$TF" "$OUT"
  [[ -s "$OUT/cuda_static_drop_pressure_0493x9e.csv" ]] || { echo '[0493x14am] ERROR x9e pressure CSV missing' >&2; exit 2; }
  grep -q 'deviceAppliedQ6ResultantClosure=B1-exact-post-periodic-device-target' "$LOG" || {
    echo '[0493x14am] ERROR x14ai-fix1 runtime marker absent' >&2; exit 2;
  }
  echo "$rc,$rep,$seed,$RUN_ROOT,$SURFACE_TENSION_SIGMA" >> "$MANIFEST"
}

if ! suite_truthy_0434 "$ANALYZE_ONLY"; then
  for ((rep=0; rep<REPLICATES; ++rep)); do
    seed=$((BASE_SEED + rep*SEED_STRIDE))
    for rc in $RADII; do
      run_one "$rc" "$rep" "$seed"
    done
  done
fi

python3 "$ANALYZER" --manifest "$MANIFEST" --output-dir "$CAMPAIGN_ROOT/analysis" \
  --sigma "$SURFACE_TENSION_SIGMA" --tail-start "$TAIL_START"

OUT_TAR="$CAMPAIGN_ROOT/0493x14am_young_laplace_two_phase_multiradius_compact.tar.gz"
TMP_LIST="$CAMPAIGN_ROOT/.compact_files_0493x14am.txt"
{
  echo manifest_0493x14am.csv
  echo analysis
  while IFS=, read -r rc rep seed dir sigma; do
    [[ "$rc" == radius_cells ]] && continue
    rel="${dir#$CAMPAIGN_ROOT/}"
    for f in \
      output/cuda_static_drop_pressure_0493x9e.csv \
      output/cuda_static_drop_velocity_0493x9e.csv \
      output/cuda_phase_interface_pressure_0493x6g.csv \
      output/cuda_phase_interface_stencil_0493x6f.csv \
      output/cuda_surface_tension_limiter_0493x9r.csv \
      output/cuda_ellipse_shape_0493x9f.csv \
      output/species_runtime_0493x14am.csv \
      logs/environment_0493x14am.env; do
      [[ -e "$CAMPAIGN_ROOT/$rel/$f" ]] && echo "$rel/$f"
    done
    find "$CAMPAIGN_ROOT/$rel/logs" -maxdepth 1 -type f -name '0493x14am_*.log' -printf "$rel/logs/%f\n" 2>/dev/null || true
    find "$CAMPAIGN_ROOT/$rel/params" -maxdepth 1 -type f -name '*.kv' -printf "$rel/params/%f\n" 2>/dev/null || true
  done < "$MANIFEST"
} > "$TMP_LIST"
tar -czf "$OUT_TAR" -C "$CAMPAIGN_ROOT" -T "$TMP_LIST"
rm -f "$TMP_LIST"

echo
echo "[0493x14am] COMPLETE"
echo "[0493x14am] report=$CAMPAIGN_ROOT/analysis/young_laplace_report_0493x14am.txt"
echo "[0493x14am] compact=$OUT_TAR"
