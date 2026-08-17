#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434

CASE_LABEL="wall_geometry_0493x9h"
RUN_MODE="${RUN_MODE:-src-q6-g-f}"
RUN_ROOT="${RUN_ROOT:-runs/0493x9h_wall_geometry_provider}"
CASES="${CASES:-domain_wall chi_wall}"
NX="${NX:-48}"
NY="${NY:-32}"
GAMMA="${GAMMA:-8}"
DT="${DT:-0.002}"
KBT="${KBT:-0.05}"
STEPS="${STEPS:-10}"
SEED="${SEED:-493920}"
LIQUID_TYPE="${LIQUID_TYPE:-1}"
LIQUID_MASS="${LIQUID_MASS:-1.0}"
SUMMARY_EVERY="${SUMMARY_EVERY:-1}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-0}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-0}"
FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-0}"
LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-density}"
LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-5}"

# x9h is deliberately passive: resident wall geometry only.
SIGMA=0.0
Q6_GF_EXTERNAL_SPECIES=1
Q6_GF_HAS_GAS_PHASE=0
Q6_GF_DENSITY_RELAXATION_TIME=0.0
Q6_GF_MIN_FILL_FRACTION="${Q6_GF_MIN_FILL_FRACTION:-0.10}"
Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE=0
Q6_GF_DENSITY_TRACTION_GAIN=0.0

THERMOSTAT_ENABLE=false
THERMOSTAT_MODE=cell_relative_rescale
THERMOSTAT_EVERY=1
THERMOSTAT_TARGET_KBT="$KBT"
THERMOSTAT_MIN_PARTICLES=3
ROTATION_ANGLE="${ROTATION_ANGLE:-1.5}"
RANDOM_ROTATION_SIGN=true
GRID_SHIFT_ENABLE=true
PROJECTION_BACKEND=cuda
PROJECTION_OPERATOR=auto_fv_cg
PROJECTION_MAX_ITERATIONS="${PROJECTION_MAX_ITERATIONS:-800}"
PROJECTION_TOLERANCE="${PROJECTION_TOLERANCE:-1e-6}"
Q6_PROJECTION_STRENGTH=1.0
Q6_STRICT="${Q6_STRICT:-1}"
WEIGHTED_RESAMPLING_ENABLE_OVERRIDE=false
SPECIES_RESAMPLING_ENABLE=false
CUDA_EMPTY_REFILL_ENABLE_OVERRIDE=false
RECORD_ENABLE=false
PARTICLE_TYPE_FILTER="$LIQUID_TYPE"

suite_defaults_common_0434
suite_compute_derived_0434

if (( NX < 16 || NY < 16 || GAMMA < 2 || STEPS < 1 )); then
  echo "[0493x9h] ERROR require NX>=16 NY>=16 GAMMA>=2 STEPS>=1" >&2
  exit 2
fi

if suite_truthy_0434 "${CLEAN_RUN_ROOT:-1}"; then
  rm -rf "$RUN_ROOT"
fi
mkdir -p "$RUN_ROOT/init" "$RUN_ROOT/chi" "$RUN_ROOT/logs"

STATE="$RUN_ROOT/init/full_liquid_0493x9h.smpcd"
python3 scripts/generate_0493x0_dam_break_state.py \
  --output "$STATE" --Lx 1.0 --Ly 1.0 --nx "$NX" --ny "$NY" --gamma "$GAMMA" \
  --column-width 0.5 --column-height 0.5 --liquid-only \
  --liquid-type "$LIQUID_TYPE" --gas-type 2 \
  --liquid-mass "$LIQUID_MASS" --gas-mass 1.0 \
  --kBT "$KBT" --seed "$SEED"

CHI="$RUN_ROOT/chi/circle_wall_${NX}x${NY}.f32"
python3 - "$CHI" "$NX" "$NY" <<'PY'
import math, struct, sys
from pathlib import Path
path=Path(sys.argv[1]); nx=int(sys.argv[2]); ny=int(sys.argv[3])
cx,cy,r=0.5,0.5,0.18
vals=[]; solid=0
for j in range(ny):
    y=(j+0.5)/ny
    for i in range(nx):
        x=(i+0.5)/nx
        inside=math.hypot(x-cx,y-cy)<=r
        # Repository Darcy convention: chi=1 fluid, chi=0 solid.
        vals.append(0.0 if inside else 1.0)
        solid += int(inside)
path.parent.mkdir(parents=True,exist_ok=True)
path.write_bytes(struct.pack(f'<{len(vals)}f',*vals))
print(f'[0493x9h-chi] file={path} grid={nx}x{ny} solidCells={solid} convention=chi1fluid_chi0solid')
PY

LIQUID_REFERENCE_CELL_MASS="$(awk -v g="$GAMMA" -v m="$LIQUID_MASS" 'BEGIN{printf "%.17g",g*m}')"

write_params() {
  local case_name="$1" topology="$2"
  local case_dir="$RUN_ROOT/$case_name"
  local params="$case_dir/params/wall_geometry_0493x9h.kv"
  mkdir -p "$case_dir/params" "$case_dir/output" "$case_dir/logs"

  cat > "$params" <<PARAMS
inputState = $STATE
outputDir = $case_dir/output
Lx = 1.0
Ly = 1.0
Nx = $NX
Ny = $NY
dt = $DT
nSteps = $STEPS
bodyAccelerationX = 0.0
bodyAccelerationY = 0.0
wallVpEnable = false
wallAccommodation = 1.0
wallThermalNoise = 0.0
surfaceTensionSigma = 0.0
phaseInterfaceASelector = type:$LIQUID_TYPE
phaseInterfaceBSelector = wall
speciesRegistryEnable = true
speciesCount = 1
species0 = $LIQUID_TYPE incompressible_liquid liquid 1.0 1.0 $LIQUID_REFERENCE_CELL_MASS
species0ResamplingEnable = false
speciesRequireRegisteredTypes = true
speciesDiagnosticsEnable = true
speciesDiagnosticsFilename = species_runtime_0493x9h.csv
speciesCellDiagnosticsEnable = false
speciesQ6Enable = true
speciesQ6Mode = free_surface_masked
speciesQ6Sensitivity = 1.0
speciesQ6FallbackMode = common
speciesQ6ComparisonTolerance = 1.0e-11
speciesQ6MinOccupancyFraction = $Q6_GF_MIN_FILL_FRACTION
PARAMS

  if [[ "$case_name" == domain_wall ]]; then
    cat >> "$params" <<'PARAMS'
bcLeft = specular
bcRight = specular
bcBottom = specular
bcTop = specular
bcX = wall
bcY = wall
openBoundarySegmentsEnable = false
openBoundarySegmentCount = 0
darcyBrinkmanEnable = false
darcyChiCollisionVpEnable = false
PARAMS
  elif [[ "$case_name" == chi_wall ]]; then
    cat >> "$params" <<PARAMS
bcLeft = periodic
bcRight = periodic
bcBottom = periodic
bcTop = periodic
bcX = periodic
bcY = periodic
openBoundarySegmentsEnable = false
openBoundarySegmentCount = 0
darcyBrinkmanEnable = true
darcyChiMode = file
darcyChiFile = $CHI
darcyChiNx = $NX
darcyChiNy = $NY
darcyChiFileFormat = float32
darcyAlphaMin = 0.0
darcyAlphaMax = 0.0
darcyQ = 0.1
darcyUSolidX = 0.0
darcyUSolidY = 0.0
darcyCostEvery = 0
darcyThreadsPerBlock = 256
darcyInitialDeactivateBelowChi = -1.0
darcyBrinkmanForcingMode = mean
darcyChiCollisionVpEnable = true
darcyChiCollisionVpMode = interface_band
darcyChiCollisionVpGamma = $GAMMA
darcyChiCollisionVpMass = $LIQUID_MASS
darcyChiCollisionVpLayers = 1
darcyChiCollisionVpThreshold = 0.5
darcyChiCollisionVpStrength = 0.0
PARAMS
  else
    echo "[0493x9h] ERROR unknown case=$case_name" >&2
    return 2
  fi

  suite_write_common_params_0434 "$RUN_MODE" >> "$params"
}

run_case() {
  local case_name="$1" topology="$2"
  local case_dir="$RUN_ROOT/$case_name"
  local params="$case_dir/params/wall_geometry_0493x9h.kv"
  local out="$case_dir/output"
  local log="$case_dir/logs/wall_geometry_0493x9h.log"
  local time_file="$case_dir/logs/wall_geometry_0493x9h.time"

  write_params "$case_name" "$topology"
  suite_export_cuda_flags_0434 "$RUN_MODE" "$topology"
  # B=wall carries no particle/gas pressure provider in x9h.
  export MPCD_Q6_PHASE_GAS_PRESSURE_0493X6G=0
  export MPCD_Q6_PHASE_GAS_PRESSURE_SCALE_0493X6G=0
  export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9A=0
  export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9B=0
  export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9C=0
  export MPCD_Q6_STATIC_DROP_DIAGNOSTICS_0493X9E=0
  export MPCD_Q6_ELLIPSE_DIAGNOSTICS_0493X9F=0

  BASE_RUN_ROOT="$case_dir"
  LIVE_VIS_CONTROL_FILE="$case_dir/livevis_control_0493x9h.kv"
  suite_prepare_livevis_control_0434 "$case_dir" "$RUN_MODE"
  suite_export_livevis_0434

  echo "[0493x9h-suite] case=$case_name topology=$topology B=wall passiveGeometry=1 sigma=0"
  suite_run_binary_0434 "$params" "$log" "$time_file" "$out"
}

for c in $CASES; do
  case "$c" in
    domain_wall) run_case "$c" closed_box ;;
    chi_wall) run_case "$c" periodic ;;
    *) echo "[0493x9h] ERROR unknown case=$c" >&2; exit 2 ;;
  esac
done

if ! suite_truthy_0434 "$PREFLIGHT_ONLY"; then
  python3 scripts/analyze_0493x9h_wall_geometry_provider.py \
    --root "$RUN_ROOT" --nx "$NX" --ny "$NY" --liquid-type "$LIQUID_TYPE"
fi
