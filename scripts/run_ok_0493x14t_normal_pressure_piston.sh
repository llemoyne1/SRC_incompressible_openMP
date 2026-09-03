#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_ok_common.sh"
suite_root_cd_0434

GENERATOR="$ROOT/scripts/generate_0493x14t_normal_pressure_piston.py"
ANALYZER="$ROOT/scripts/analyze_0493x14t_normal_pressure_piston.py"
for f in "$GENERATOR" "$ANALYZER" "$ROOT/scripts/analyze_0493x6g_phase_gas_pressure.py"; do
  [[ -f "$f" ]] || { echo "[0493x14t] ERROR missing $f" >&2; exit 2; }
done

# x14t fix2: rotate piston to the actually qualified resident wall-channel family.
#   x periodic, y wall-like; horizontal slab; pressure transfer measured in y.
# No C++/CUDA change. ./livevis_control.kv is read only.

CASE_LABEL="${CASE_LABEL:-0493x14t_normal_pressure_piston}"
RUN_MODE="src-q6-g-f"
TOPOLOGY="wall"

Lx="${Lx:-1.5625}"; Ly="${Ly:-1.0}"; NX="${NX:-400}"; NY="${NY:-256}"
GAMMA="${GAMMA:-20}"; LIQUID_COUNT="${LIQUID_COUNT:-20}"
SLAB_WIDTH_CELLS="${SLAB_WIDTH_CELLS:-80}"; SLAB_CENTER_CELL="${SLAB_CENTER_CELL:-128}"
LIQUID_TYPE="${LIQUID_TYPE:-1}"; GAS_TYPE="${GAS_TYPE:-2}"
LIQUID_MASS="${LIQUID_MASS:-1.0}"; GAS_MASS="${GAS_MASS:-0.1}"
LIQUID_KBT="${LIQUID_KBT:-0.02}"; GAS_KBT="${GAS_KBT:-0.08}"
KBT="${KBT:-$GAS_KBT}"; THERMOSTAT_TARGET_KBT="${THERMOSTAT_TARGET_KBT:-$GAS_KBT}"
DT="${DT:-0.002}"; STEPS="${STEPS:-300}"; SUMMARY_EVERY="${SUMMARY_EVERY:-10}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-100}"; SEED="${SEED:-493150}"
CASES="${CASES:-balanced bottom_high top_high}"
FIT_STEP_MIN="${FIT_STEP_MIN:-50}"; FIT_STEP_MAX="${FIT_STEP_MAX:-150}"

ROTATION_ANGLE="${ROTATION_ANGLE:-1.5707963267948966}"
RANDOM_ROTATION_SIGN="${RANDOM_ROTATION_SIGN:-true}"
GRID_SHIFT_ENABLE="${GRID_SHIFT_ENABLE:-true}"
THERMOSTAT_ENABLE="${THERMOSTAT_ENABLE:-true}"
THERMOSTAT_MODE="${THERMOSTAT_MODE:-cell_relative_rescale}"
THERMOSTAT_EVERY="${THERMOSTAT_EVERY:-1}"
THERMOSTAT_MIN_PARTICLES="${THERMOSTAT_MIN_PARTICLES:-3}"

SURFACE_TENSION_SIGMA=5000
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
LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-density}"; LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-20}"
LIVE_VIS_NX="${LIVE_VIS_NX:-200}"; LIVE_VIS_NY="${LIVE_VIS_NY:-128}"
LIVE_VIS_COLORMAP="${LIVE_VIS_COLORMAP:-hot}"; LIVE_VIS_CLIP="${LIVE_VIS_CLIP:--1}"
LIVE_VIS_GAIN="${LIVE_VIS_GAIN:-1.0}"; LIVE_VIS_SMOOTH_PASSES="${LIVE_VIS_SMOOTH_PASSES:-1}"
LIVE_VIS_WINDOW_SCALE="${LIVE_VIS_WINDOW_SCALE:-1}"; LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-0}"
RECORD_ENABLE="${RECORD_ENABLE:-false}"; RECORD_FIELDS="${RECORD_FIELDS:-mass}"; RECORD_EVERY="${RECORD_EVERY:-100}"
FILTER_MODE="${FILTER_MODE:-none}"; FILTER_SAMPLE_EVERY="${FILTER_SAMPLE_EVERY:-100}"
FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-0}"; PARTICLE_TYPE_FILTER="${PARTICLE_TYPE_FILTER:--1}"

BIN="${BIN:-${SRC_MPCD_DEFAULT_BIN_0434:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}}"
CAMPAIGN_ROOT="${CAMPAIGN_ROOT:-runs/0493x14t_normal_pressure_piston}"

GEN_CASE="tg"; U0=0.0; VELOCITY_MODE="zero"; PARTICLE_MASS="$GAS_MASS"
BACKGROUND_TYPE="$GAS_TYPE"; INACTIVE_TYPE="$GAS_TYPE"; TG_HOLE_ENABLE=false
SPECIES_RESAMPLING_ENABLE=false; SPECIES_RESIDENT_MODE=off; RESAMPLING_HOST_PATCHBACK_ENABLE=0
MASS_RECONDITION_ENABLE=0; RESAMPLING_THERMAL_RENORMALIZATION_ENABLE=false
RESAMPLING_MASS_GUARD_ENABLE=false; VIRIAL_DENSITY_KICK_ENABLE=false
Q6_GF_EXTERNAL_SPECIES=1; Q6_GF_HAS_GAS_PHASE=1; Q6_GF_MIN_FILL_FRACTION="$SPECIES_Q6_MIN_FILL_FRACTION"
RUN_OK_REFERENCE_PARTICLE_MASS="$LIQUID_MASS"; RUN_OK_GENERATOR_PATH="$GENERATOR"
export RUN_OK_REFERENCE_PARTICLE_MASS RUN_OK_GENERATOR_PATH

suite_defaults_common_0434
suite_compute_derived_0434

read -r H CELL_AREA SLAB_WIDTH P_REF RHO_L <<<"$(python3 - "$Lx" "$Ly" "$NX" "$NY" "$SLAB_WIDTH_CELLS" "$GAMMA" "$LIQUID_MASS" "$GAS_KBT" <<'PY'
import sys
lx,ly=float(sys.argv[1]),float(sys.argv[2]); nx,ny=int(sys.argv[3]),int(sys.argv[4]); wc=int(sys.argv[5])
g=float(sys.argv[6]); ml=float(sys.argv[7]); tg=float(sys.argv[8]); hx=lx/nx; hy=ly/ny
if abs(hx-hy)>1e-12*max(1.0,abs(hx),abs(hy)): raise SystemExit("[0493x14t] square cells required")
A=hx*hy
print(f"{hy:.17g} {A:.17g} {wc*hy:.17g} {g*tg/A:.17g} {g*ml/A:.17g}")
PY
)"

if suite_truthy_0434 "$CLEAN_RUN_ROOT"; then rm -rf "$CAMPAIGN_ROOT"; fi
mkdir -p "$CAMPAIGN_ROOT"/{analysis,logs}
MANIFEST="$CAMPAIGN_ROOT/manifest_0493x14t.csv"
echo "case,gasBottomCount,gasTopCount,pBottom,pTop,deltaP,rhoLiquid,slabWidth,aTheory,runRoot,speciesCsv" > "$MANIFEST"

case_counts() {
  case "$1" in
    balanced) echo "20 20" ;;
    bottom_high) echo "22 18" ;;
    top_high) echo "18 22" ;;
    *) echo "[0493x14t] ERROR unknown case=$1" >&2; return 2 ;;
  esac
}

configure_x14s_env() {
  suite_export_cuda_flags_0434 "$RUN_MODE" "$TOPOLOGY"
  run_ok_surface_export_off_flags_0493x13zi
  export MPCD_Q6_PHASE_GAS_PRESSURE_0493X6G=1
  export MPCD_Q6_PHASE_GAS_PRESSURE_MODE_0493X6G=eos_accessible_volume
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

run_case() {
  local cname="$1" gb gt
  read -r gb gt <<<"$(case_counts "$cname")"
  local rr="$CAMPAIGN_ROOT/$cname"
  local state="$rr/init/${CASE_LABEL}_${cname}.smpcd"
  local params="$rr/params/${CASE_LABEL}_${cname}.kv"
  local out="$rr/output"; local log="$rr/logs/${CASE_LABEL}_${cname}.log"; local tf="$rr/logs/${CASE_LABEL}_${cname}.time"
  local analysis="$rr/analysis"
  suite_prepare_dirs_0434 "$rr"; mkdir -p "$out" "$analysis"

  python3 "$GENERATOR" --output "$state" --Lx "$Lx" --Ly "$Ly" --nx "$NX" --ny "$NY" \
    --liquid-count "$LIQUID_COUNT" --gas-bottom-count "$gb" --gas-top-count "$gt" \
    --slab-width-cells "$SLAB_WIDTH_CELLS" --slab-center-cell "$SLAB_CENTER_CELL" \
    --liquid-type "$LIQUID_TYPE" --gas-type "$GAS_TYPE" --liquid-mass "$LIQUID_MASS" --gas-mass "$GAS_MASS" \
    --liquid-kBT "$LIQUID_KBT" --gas-kBT "$GAS_KBT" --seed "$SEED"

  local pb pt dp ath
  read -r pb pt dp ath <<<"$(python3 - "$gb" "$gt" "$GAS_KBT" "$CELL_AREA" "$RHO_L" "$SLAB_WIDTH" <<'PY'
import sys
nb,nt=int(sys.argv[1]),int(sys.argv[2]); k=float(sys.argv[3]); A=float(sys.argv[4]); rho=float(sys.argv[5]); W=float(sys.argv[6])
pb=nb*k/A; pt=nt*k/A; dp=pb-pt
print(f"{pb:.17g} {pt:.17g} {dp:.17g} {dp/(rho*W):.17g}")
PY
)"
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
speciesDiagnosticsFilename = species_runtime_0493x14t.csv
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

  configure_x14s_env
  suite_prepare_livevis_control_0434 "$rr" "$RUN_MODE"
  suite_export_livevis_0434
  suite_write_env_file_0434 "$rr/logs/environment_0493x14t.env" "$RUN_MODE"
  cat >> "$rr/logs/environment_0493x14t.env" <<META
CASE=$cname
ORIENTATION=horizontal_slab_motion_y
GAS_BOTTOM_COUNT=$gb
GAS_TOP_COUNT=$gt
P_BOTTOM=$pb
P_TOP=$pt
DELTA_P=$dp
RHO_LIQUID=$RHO_L
SLAB_WIDTH=$SLAB_WIDTH
A_THEORY_Y=$ath
SURFACE_TENSION_SIGMA=0
MPCD_Q6_PHASE_GAS_PRESSURE_MODE_0493X6G=eos_accessible_volume
MPCD_X14L_GAS_SPECULAR_REFLECTION=1
META

  echo
  echo "===== 0493x14t FIX2 case=$cname ====="
  echo "PATHS: runner=$ROOT/scripts/run_ok_0493x14t_normal_pressure_piston.sh"
  echo "       generator=$GENERATOR analyzer=$ANALYZER"
  echo "       state=$state params=$params output=$out"
  echo "GEOM:  horizontal slab, motion=y; grid=${NX}x${NY} h=$H; x=periodic y=specular walls; slabWidth/h=$SLAB_WIDTH_CELLS"
  echo "GAS:   Nbottom=$gb Ntop=$gt pBottom=$pb pTop=$pt dP=$dp"
  echo "LIQ:   Ncell=$LIQUID_COUNT rho=$RHO_L width=$SLAB_WIDTH"
  echo "THEORY: a_y=dP/(rhoL*W)=$ath ; expected Vy(t=0.2)=$(awk -v a="$ath" 'BEGIN{printf "%.9g",a*0.2}')"
  echo "CHAIN: x6g=eos_accessible_volume + gas specular; liquid x10o/CIC/Q2/x10p/q/x10u/x10v/x12a unchanged"
  echo "CAP:   sigma=0"
  echo "RUN:   topology=$TOPOLOGY steps=$STEPS dt=$DT summaryEvery=$SUMMARY_EVERY dumpEvery=$DUMP_STATE_EVERY"
  echo "NOTE:  ./livevis_control.kv is user-owned and not modified"
  echo "===================================="

  echo "$cname,$gb,$gt,$pb,$pt,$dp,$RHO_L,$SLAB_WIDTH,$ath,$rr,$out/species_runtime_0493x14t.csv" >> "$MANIFEST"
  suite_run_binary_0434 "$params" "$log" "$tf" "$out"
  if suite_truthy_0434 "$PREFLIGHT_ONLY"; then return 0; fi

  if [[ -s "$out/cuda_phase_interface_pressure_0493x6g.csv" && -s "$out/cuda_phase_interface_stencil_0493x6f.csv" ]]; then
    python3 "$ROOT/scripts/analyze_0493x6g_phase_gas_pressure.py" \
      --pressure "$out/cuda_phase_interface_pressure_0493x6g.csv" \
      --stencil "$out/cuda_phase_interface_stencil_0493x6f.csv" \
      --json "$analysis/phase_interface_gas_pressure_0493x14t.json"
  fi
}

for c in $CASES; do run_case "$c"; done

if suite_truthy_0434 "$PREFLIGHT_ONLY"; then
  echo "[0493x14t] PREFLIGHT_ONLY complete"; exit 0
fi

python3 "$ANALYZER" --campaign-root "$CAMPAIGN_ROOT" --manifest "$MANIFEST" \
  --liquid-type "$LIQUID_TYPE" --fit-step-min "$FIT_STEP_MIN" --fit-step-max "$FIT_STEP_MAX"

OUT_TAR="$CAMPAIGN_ROOT/0493x14t_normal_pressure_piston_compact.tar.gz"
FILES=(manifest_0493x14t.csv analysis)
for c in $CASES; do
  FILES+=("$c/analysis" "$c/output/species_runtime_0493x14t.csv"
          "$c/output/cuda_phase_interface_pressure_0493x6g.csv"
          "$c/output/cuda_phase_interface_stencil_0493x6f.csv"
          "$c/logs/${CASE_LABEL}_${c}.log")
done
tar -czf "$OUT_TAR" -C "$CAMPAIGN_ROOT" "${FILES[@]}"

echo
echo "[0493x14t] DONE"
echo "[0493x14t] return: $CAMPAIGN_ROOT/analysis/normal_pressure_summary_0493x14t.json"
echo "[0493x14t] return: $OUT_TAR"
