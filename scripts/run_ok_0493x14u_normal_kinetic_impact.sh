#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_ok_common.sh"
suite_root_cd_0434

GENERATOR="$ROOT/scripts/generate_0493x14u_normal_kinetic_impact.py"
ANALYZER="$ROOT/scripts/analyze_0493x14u_normal_kinetic_impact.py"
for f in "$GENERATOR" "$ANALYZER" "$ROOT/scripts/analyze_0493x6g_phase_gas_pressure.py"; do
  [[ -f "$f" ]] || { echo "[0493x14u] ERROR missing $f" >&2; exit 2; }
done

# =============================================================================
# 0493x14u — normal kinetic gas/liquid momentum-transfer benchmark
#
# Same already-qualified x14t resident boundary family:
#   x periodic, y specular walls, horizontal liquid slab.
#
# Thermodynamic state is balanced everywhere: gas occupancy=20 on both sides.
# Only a finite gas band adjacent to one interface receives normal mean drift.
#
# Primary isolation:
#   x6gMode=constant  -> pGas contribution is exactly zero.
# Secondary:
#   x6gMode=eos_accessible_volume -> production x14s response.
#
# No C++/CUDA change. No new runtime diagnostic. livevis_control.kv read only.
# =============================================================================

CASE_LABEL="${CASE_LABEL:-0493x14u_normal_kinetic_impact}"
RUN_MODE="src-q6-g-f"
TOPOLOGY="wall"

Lx="${Lx:-1.5625}"; Ly="${Ly:-1.0}"; NX="${NX:-400}"; NY="${NY:-256}"
GAMMA="${GAMMA:-20}"; OCCUPANCY="${OCCUPANCY:-20}"
SLAB_WIDTH_CELLS="${SLAB_WIDTH_CELLS:-80}"; SLAB_CENTER_CELL="${SLAB_CENTER_CELL:-128}"
IMPACT_BAND_CELLS="${IMPACT_BAND_CELLS:-24}"; IMPACT_SPEED="${IMPACT_SPEED:-0.1}"

LIQUID_TYPE="${LIQUID_TYPE:-1}"; GAS_TYPE="${GAS_TYPE:-2}"
LIQUID_MASS="${LIQUID_MASS:-1.0}"; GAS_MASS="${GAS_MASS:-0.1}"
LIQUID_KBT="${LIQUID_KBT:-0.02}"; GAS_KBT="${GAS_KBT:-0.08}"
KBT="${KBT:-$GAS_KBT}"; THERMOSTAT_TARGET_KBT="${THERMOSTAT_TARGET_KBT:-$GAS_KBT}"

DT="${DT:-0.002}"; STEPS="${STEPS:-60}"; SUMMARY_EVERY="${SUMMARY_EVERY:-1}"
# Keep this benchmark compact: species runtime is sufficient for the primary
# momentum budget.  Explicitly request dumps only if needed later.
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-0}"
SEED="${SEED:-493150}"
CASES="${CASES:-static bottom_impact top_impact}"
X6G_MODES="${X6G_MODES:-constant eos_accessible_volume}"
FIT_STEP_MIN="${FIT_STEP_MIN:-1}"; FIT_STEP_MAX="${FIT_STEP_MAX:-20}"

ROTATION_ANGLE="${ROTATION_ANGLE:-1.5707963267948966}"
RANDOM_ROTATION_SIGN="${RANDOM_ROTATION_SIGN:-true}"
GRID_SHIFT_ENABLE="${GRID_SHIFT_ENABLE:-true}"
THERMOSTAT_ENABLE="${THERMOSTAT_ENABLE:-true}"
THERMOSTAT_MODE="${THERMOSTAT_MODE:-cell_relative_rescale}"
THERMOSTAT_EVERY="${THERMOSTAT_EVERY:-1}"
THERMOSTAT_MIN_PARTICLES="${THERMOSTAT_MIN_PARTICLES:-3}"

SURFACE_TENSION_SIGMA=0
SURFACE_TENSION_MIN_RADIUS_CELLS="${SURFACE_TENSION_MIN_RADIUS_CELLS:-4}"
PHASE_INTERFACE_KINETIC_REFLECTION_FRACTION="${PHASE_INTERFACE_KINETIC_REFLECTION_FRACTION:-1.0}"
PHASE_INTERFACE_EVAPORATION_TARGET_TYPE="${PHASE_INTERFACE_EVAPORATION_TARGET_TYPE:--1}"
PHASE_INTERFACE_CONTACT_ANGLE_DEG="${PHASE_INTERFACE_CONTACT_ANGLE_DEG:--1}"
X12A_LOCAL_THERMAL_RADIUS_CELLS="${X12A_LOCAL_THERMAL_RADIUS_CELLS:-25.298221281347036}"
PHASE_INTERFACE_A_SELECTOR="type:${LIQUID_TYPE}"; PHASE_INTERFACE_B_SELECTOR="type:${GAS_TYPE}"

LIQUID_Q6_STRENGTH="${LIQUID_Q6_STRENGTH:-1.0}"; GAS_Q6_STRENGTH="${GAS_Q6_STRENGTH:-0.0}"
SPECIES_Q6_MIN_FILL_FRACTION="${SPECIES_Q6_MIN_FILL_FRACTION:-0.10}"
Q6_GF_DENSITY_RELAXATION_TIME="${Q6_GF_DENSITY_RELAXATION_TIME:-0.25}"
Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE="${Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE:-1}"
Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES="${Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES:-3.0}"
Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES="${Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES:-6.0}"
Q6_GF_DENSITY_TRACTION_GAIN="${Q6_GF_DENSITY_TRACTION_GAIN:-1.0}"

PROJECTION_BACKEND="${PROJECTION_BACKEND:-cuda}"
PROJECTION_MAX_ITERATIONS="${PROJECTION_MAX_ITERATIONS:-800}"
PROJECTION_TOLERANCE="${PROJECTION_TOLERANCE:-1.0e-5}"
Q6_PROJECTION_STRENGTH="${Q6_PROJECTION_STRENGTH:-1.0}"; Q6_STRICT="${Q6_STRICT:-1}"

LIVE_PROGRESS="${LIVE_PROGRESS:-1}"; PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"; CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-0}"; LIVE_VIS_CONTROL_FILE="$ROOT/livevis_control.kv"
LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-Uy}"; LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-5}"
LIVE_VIS_NX="${LIVE_VIS_NX:-200}"; LIVE_VIS_NY="${LIVE_VIS_NY:-128}"
LIVE_VIS_COLORMAP="${LIVE_VIS_COLORMAP:-bwr}"; LIVE_VIS_CLIP="${LIVE_VIS_CLIP:--1}"
LIVE_VIS_GAIN="${LIVE_VIS_GAIN:-1.0}"; LIVE_VIS_SMOOTH_PASSES="${LIVE_VIS_SMOOTH_PASSES:-1}"
LIVE_VIS_WINDOW_SCALE="${LIVE_VIS_WINDOW_SCALE:-1}"; LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-0}"
RECORD_ENABLE="${RECORD_ENABLE:-false}"; RECORD_FIELDS="${RECORD_FIELDS:-mass}"
RECORD_EVERY="${RECORD_EVERY:-100}"; FILTER_MODE="${FILTER_MODE:-none}"
FILTER_SAMPLE_EVERY="${FILTER_SAMPLE_EVERY:-100}"; FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-0}"
PARTICLE_TYPE_FILTER="${PARTICLE_TYPE_FILTER:--1}"

BIN="${BIN:-${SRC_MPCD_DEFAULT_BIN_0434:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}}"
CAMPAIGN_ROOT="${CAMPAIGN_ROOT:-runs/0493x14u_normal_kinetic_impact}"

GEN_CASE="tg"; U0=0.0; VELOCITY_MODE="zero"; PARTICLE_MASS="$GAS_MASS"
BACKGROUND_TYPE="$GAS_TYPE"; INACTIVE_TYPE="$GAS_TYPE"; TG_HOLE_ENABLE=false
SPECIES_RESAMPLING_ENABLE=false; SPECIES_RESIDENT_MODE=off
RESAMPLING_HOST_PATCHBACK_ENABLE=0; MASS_RECONDITION_ENABLE=0
RESAMPLING_THERMAL_RENORMALIZATION_ENABLE=false; RESAMPLING_MASS_GUARD_ENABLE=false
VIRIAL_DENSITY_KICK_ENABLE=false
Q6_GF_EXTERNAL_SPECIES=1; Q6_GF_HAS_GAS_PHASE=1
Q6_GF_MIN_FILL_FRACTION="$SPECIES_Q6_MIN_FILL_FRACTION"
RUN_OK_REFERENCE_PARTICLE_MASS="$LIQUID_MASS"; RUN_OK_GENERATOR_PATH="$GENERATOR"
export RUN_OK_REFERENCE_PARTICLE_MASS RUN_OK_GENERATOR_PATH

suite_defaults_common_0434
suite_compute_derived_0434

read -r H CELL_AREA P_REF <<<"$(python3 - "$Lx" "$Ly" "$NX" "$NY" "$OCCUPANCY" "$GAS_KBT" <<'PY'
import sys
lx,ly=float(sys.argv[1]),float(sys.argv[2]); nx,ny=int(sys.argv[3]),int(sys.argv[4])
occ=float(sys.argv[5]); k=float(sys.argv[6]); hx=lx/nx; hy=ly/ny
if abs(hx-hy)>1e-12*max(1.0,abs(hx),abs(hy)): raise SystemExit("[0493x14u] square cells required")
A=hx*hy
print(f"{hy:.17g} {A:.17g} {occ*k/A:.17g}")
PY
)"

if suite_truthy_0434 "$CLEAN_RUN_ROOT"; then rm -rf "$CAMPAIGN_ROOT"; fi
mkdir -p "$CAMPAIGN_ROOT"/{analysis,logs,states}

# Generate each physical initial state only once; reuse it across x6g modes.
for c in $CASES; do
  state="$CAMPAIGN_ROOT/states/${CASE_LABEL}_${c}.smpcd"
  python3 "$GENERATOR" \
    --output "$state" --case "$c" \
    --Lx "$Lx" --Ly "$Ly" --nx "$NX" --ny "$NY" \
    --occupancy "$OCCUPANCY" --slab-width-cells "$SLAB_WIDTH_CELLS" \
    --slab-center-cell "$SLAB_CENTER_CELL" --impact-band-cells "$IMPACT_BAND_CELLS" \
    --impact-speed "$IMPACT_SPEED" --liquid-type "$LIQUID_TYPE" --gas-type "$GAS_TYPE" \
    --liquid-mass "$LIQUID_MASS" --gas-mass "$GAS_MASS" \
    --liquid-kBT "$LIQUID_KBT" --gas-kBT "$GAS_KBT" --seed "$SEED"
done

MANIFEST="$CAMPAIGN_ROOT/manifest_0493x14u.csv"
echo "x6gMode,case,impactSpeed,impactBandCells,aTheoryEmpirical,aTheoryMaxwell,initialLiquidPy,initialGasPy,runRoot,speciesCsv" > "$MANIFEST"

configure_env() {
  local x6g_mode="$1"
  suite_export_cuda_flags_0434 "$RUN_MODE" "$TOPOLOGY"
  run_ok_surface_export_off_flags_0493x13zi
  export MPCD_Q6_PHASE_GAS_PRESSURE_0493X6G=1
  export MPCD_Q6_PHASE_GAS_PRESSURE_MODE_0493X6G="$x6g_mode"
  export MPCD_Q6_PHASE_GAS_PRESSURE_REFERENCE_0493X6G="$P_REF"
  export MPCD_Q6_PHASE_GAS_PRESSURE_CONSTANT_0493X6G="$P_REF"
  export MPCD_Q6_PHASE_GAS_PRESSURE_SCALE_0493X6G=1

  export MPCD_X10O_Q6_THERMAL_INTERFACE_WALL=1
  export MPCD_X10O_THERMAL_PARTICLE_MASS="$LIQUID_MASS"
  export MPCD_X10O_THERMAL_SIGMAS="${X10O_THERMAL_SIGMAS:-3.0}"
  export MPCD_X10O_THERMAL_MAX_CELLS="${X10O_THERMAL_MAX_CELLS:-0.75}"
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
  export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9A=0
  export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9B=0
  export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9C=0
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WORKSPACE_DOWNLOAD_0272=1
}

read_meta_field() {
  python3 - "$1" "$2" <<'PY'
import json,sys
d=json.load(open(sys.argv[1]))
v=d[sys.argv[2]]
print(f"{v:.17g}" if isinstance(v,(int,float)) else v)
PY
}

run_one() {
  local mode="$1" c="$2"
  local rr="$CAMPAIGN_ROOT/$mode/$c"
  local state="$CAMPAIGN_ROOT/states/${CASE_LABEL}_${c}.smpcd"
  local meta="${state}.json"
  local params="$rr/params/${CASE_LABEL}_${mode}_${c}.kv"
  local out="$rr/output"; local log="$rr/logs/${CASE_LABEL}_${mode}_${c}.log"
  local tf="$rr/logs/${CASE_LABEL}_${mode}_${c}.time"; local analysis="$rr/analysis"
  suite_prepare_dirs_0434 "$rr"; mkdir -p "$out" "$analysis"

  local lref gref
  lref="$(awk -v g="$GAMMA" -v m="$LIQUID_MASS" 'BEGIN{printf "%.17g",g*m}')"
  gref="$(awk -v g="$GAMMA" -v m="$GAS_MASS" 'BEGIN{printf "%.17g",g*m}')"

  cat > "$params" <<PARAMS
inputState = $state
outputDir = $out
Lx = $Lx
Ly = $Ly
Nx = $NX
Ny = $NY
dt = $DT
nSteps = $STEPS
bcLeft = periodic
bcRight = periodic
bcBottom = specular
bcTop = specular
bcX = periodic
bcY = wall
openBoundarySegmentsEnable = false
openBoundarySegmentCount = 0
bodyAccelerationX = 0.0
bodyAccelerationY = 0.0
wallVpEnable = false
wallAccommodation = 1.0
wallThermalNoise = 0.0
speciesRegistryEnable = true
speciesCount = 2
species0 = $LIQUID_TYPE incompressible_liquid liquid $LIQUID_Q6_STRENGTH 1.0 $lref
species0ResamplingEnable = false
species0ThermostatTargetKBT = $LIQUID_KBT
species1 = $GAS_TYPE compressible_gas gas $GAS_Q6_STRENGTH 0.0 $gref
species1ResamplingEnable = false
species1ThermostatTargetKBT = $GAS_KBT
speciesRequireRegisteredTypes = true
speciesThermostatEnable = true
speciesDiagnosticsEnable = true
speciesDiagnosticsFilename = species_runtime_0493x14u.csv
speciesCellDiagnosticsEnable = false
speciesQ6Sensitivity = 1.0
speciesQ6FallbackMode = common
speciesQ6ComparisonTolerance = 1.0e-11
PARAMS
  suite_write_common_params_0434 "$RUN_MODE" >> "$params"
  run_ok_surface_append_params_0493x13zi "$params" "$PHASE_INTERFACE_A_SELECTOR" "$PHASE_INTERFACE_B_SELECTOR"
  cat >> "$params" <<'PARAMS'
phaseInterfaceKineticBilateralRelocation = true
PARAMS

  configure_env "$mode"
  suite_prepare_livevis_control_0434 "$rr" "$RUN_MODE"
  suite_export_livevis_0434
  suite_write_env_file_0434 "$rr/logs/environment_0493x14u.env" "$RUN_MODE"

  local aemp amax pl0 pg0
  aemp="$(read_meta_field "$meta" empiricalInitialAccelerationTheory)"
  amax="$(read_meta_field "$meta" maxwellInitialAccelerationTheory)"
  pl0="$(read_meta_field "$meta" initialLiquidPy)"
  pg0="$(read_meta_field "$meta" initialGasPy)"

  cat >> "$rr/logs/environment_0493x14u.env" <<META
CASE=$c
X6G_MODE=$mode
IMPACT_SPEED=$IMPACT_SPEED
IMPACT_BAND_CELLS=$IMPACT_BAND_CELLS
A_THEORY_EMPIRICAL=$aemp
A_THEORY_MAXWELL=$amax
INITIAL_LIQUID_PY=$pl0
INITIAL_GAS_PY=$pg0
SURFACE_TENSION_SIGMA=0
MPCD_X14L_GAS_SPECULAR_REFLECTION=1
GAS_WALL_IMPULSE_FEEDBACK=NOT_APPLIED
META

  echo
  echo "===== 0493x14u mode=$mode case=$c ====="
  echo "PATHS: runner=$ROOT/scripts/run_ok_0493x14u_normal_kinetic_impact.sh"
  echo "       generator=$GENERATOR analyzer=$ANALYZER"
  echo "       state=$state params=$params output=$out"
  echo "GEOM:  x periodic, y specular walls, horizontal liquid slab; band=${IMPACT_BAND_CELLS}h"
  echo "STATE: occupancy=$OCCUPANCY everywhere; pThermo bottom=top=$P_REF; Uimpact=$IMPACT_SPEED"
  echo "THEORY: aKin empirical=$aemp Maxwell=$amax"
  echo "X6G:   mode=$mode pRef=$P_REF ; constant mode => gas pressure contribution identically zero"
  echo "CHAIN: gas=x14l specular (wall impulse NOT applied); liquid chain unchanged; sigma=0"
  echo "RUN:   steps=$STEPS dt=$DT summaryEvery=$SUMMARY_EVERY dumpEvery=$DUMP_STATE_EVERY"
  echo "NOTE:  livevis_control.kv is user-owned/read-only"
  echo "=========================================="

  echo "$mode,$c,$IMPACT_SPEED,$IMPACT_BAND_CELLS,$aemp,$amax,$pl0,$pg0,$rr,$out/species_runtime_0493x14u.csv" >> "$MANIFEST"

  suite_run_binary_0434 "$params" "$log" "$tf" "$out"
  if suite_truthy_0434 "$PREFLIGHT_ONLY"; then return 0; fi

  if [[ -s "$out/cuda_phase_interface_pressure_0493x6g.csv" && -s "$out/cuda_phase_interface_stencil_0493x6f.csv" ]]; then
    python3 "$ROOT/scripts/analyze_0493x6g_phase_gas_pressure.py" \
      --pressure "$out/cuda_phase_interface_pressure_0493x6g.csv" \
      --stencil "$out/cuda_phase_interface_stencil_0493x6f.csv" \
      --json "$analysis/phase_interface_gas_pressure_0493x14u.json"
  fi
}

for mode in $X6G_MODES; do
  for c in $CASES; do
    run_one "$mode" "$c"
  done
done

if suite_truthy_0434 "$PREFLIGHT_ONLY"; then
  echo "[0493x14u] PREFLIGHT_ONLY complete"
  exit 0
fi

python3 "$ANALYZER" \
  --campaign-root "$CAMPAIGN_ROOT" --manifest "$MANIFEST" \
  --liquid-type "$LIQUID_TYPE" --gas-type "$GAS_TYPE" \
  --fit-step-min "$FIT_STEP_MIN" --fit-step-max "$FIT_STEP_MAX"

OUT_TAR="$CAMPAIGN_ROOT/0493x14u_normal_kinetic_impact_compact.tar.gz"
FILES=(manifest_0493x14u.csv analysis)
for mode in $X6G_MODES; do
  for c in $CASES; do
    FILES+=("$mode/$c/analysis"
            "$mode/$c/output/species_runtime_0493x14u.csv"
            "$mode/$c/output/cuda_phase_interface_pressure_0493x6g.csv"
            "$mode/$c/output/cuda_phase_interface_stencil_0493x6f.csv"
            "$mode/$c/logs/${CASE_LABEL}_${mode}_${c}.log")
  done
done
tar -czf "$OUT_TAR" -C "$CAMPAIGN_ROOT" "${FILES[@]}"

echo
echo "[0493x14u] DONE"
echo "[0493x14u] primary: $CAMPAIGN_ROOT/analysis/normal_kinetic_impact_summary_0493x14u.json"
echo "[0493x14u] return:  $OUT_TAR"
