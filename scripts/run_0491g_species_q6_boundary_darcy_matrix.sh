#!/usr/bin/env bash
set -uo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434

BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_0400}"
RUN_ROOT="${RUN_ROOT:-runs/0491g_species_q6_boundary_darcy}"
NX="${NX:-8}"
NY="${NY:-4}"
GAMMA="${GAMMA:-4}"
STEPS="${STEPS:-2}"
SUMMARY_EVERY="${SUMMARY_EVERY:-1}"
DT="${DT:-0.01}"
KBT="${KBT:-0.005}"
SEED="${SEED:-49107}"
UIN="${UIN:-0.02}"
LIQUID_TO_GAS_MASS_RATIO="${LIQUID_TO_GAS_MASS_RATIO:-10.0}"
GAS_PARTICLE_MASS="${GAS_PARTICLE_MASS:-1.0}"
LIQUID_PARTICLE_MASS="${LIQUID_PARTICLE_MASS:-$(awk -v mg="$GAS_PARTICLE_MASS" -v r="$LIQUID_TO_GAS_MASS_RATIO" 'BEGIN{printf "%.17g", mg*r}')}"
SPECIES_Q6_COMPARISON_TOLERANCE="${SPECIES_Q6_COMPARISON_TOLERANCE:-1.0e-11}"

if (( GAMMA < 2 )); then
  echo "[0491g] ERROR GAMMA must be >=2 to seed liquid and gas in every cell" >&2
  exit 2
fi

if [[ "${CLEAN_RUN_ROOT:-1}" == 1 ]]; then
  rm -rf "$RUN_ROOT"
fi
mkdir -p "$RUN_ROOT/init" "$RUN_ROOT/logs"

suite_ensure_binary_0434

STATE="$RUN_ROOT/init/species_q6_boundary_darcy_0491g.smpcd"
python3 - "$STATE" "$NX" "$NY" "$GAMMA" "$GAS_PARTICLE_MASS" "$LIQUID_PARTICLE_MASS" "$SEED" <<'PY_STATE_0491G'
import math
import os
import struct
import sys

state_path, nx, ny, gamma, gas_mass, liquid_mass, seed = sys.argv[1:]
nx, ny, gamma, seed = int(nx), int(ny), int(gamma), int(seed)
gas_mass, liquid_mass = float(gas_mass), float(liquid_mass)

x = []
y = []
vx = []
vy = []
typ = []
mass = []
role = []

for j in range(ny):
    for i in range(nx):
        xc = (i + 0.5) / nx
        yc = (j + 0.5) / ny
        ux = 0.025 * math.sin(2.0 * math.pi * xc) * math.cos(2.0 * math.pi * yc)
        uy = 0.015 * math.cos(2.0 * math.pi * xc) * math.sin(2.0 * math.pi * yc)
        liquid_dvx = 0.001 * math.sin(2.0 * math.pi * (xc + yc))
        liquid_dvy = 0.001 * math.cos(2.0 * math.pi * (xc - yc))
        gas_dvx = -liquid_mass * liquid_dvx / ((gamma - 1) * gas_mass)
        gas_dvy = -liquid_mass * liquid_dvy / ((gamma - 1) * gas_mass)
        for k in range(gamma):
            px = (i + (k + 0.5) / gamma) / nx
            py = (j + ((k * 3 + 1) % gamma + 0.5) / gamma) / ny
            x.append(px)
            y.append(py)
            if k == 0:
                typ.append(1)
                mass.append(liquid_mass)
                vx.append(ux + liquid_dvx)
                vy.append(uy + liquid_dvy)
            else:
                typ.append(2)
                mass.append(gas_mass)
                vx.append(ux + gas_dvx)
                vy.append(uy + gas_dvy)
            role.append(1)

os.makedirs(os.path.dirname(state_path) or ".", exist_ok=True)
magic = b"SRCMPCD_STATE" + b"\0" * (16 - len("SRCMPCD_STATE"))
reserved = [0] * 8
reserved[0] = 1
reserved[1] = 1
n = len(x)
with open(state_path, "wb") as f:
    f.write(magic)
    f.write(struct.pack("<IIIIQIIII", 2, 0x01020304, 2, 1, n, 1, 1, 8, 4))
    f.write(struct.pack("<8Q", *reserved))
    for arr, fmt in [
        (x, "d"), (y, "d"), (vx, "d"), (vy, "d"),
        (typ, "I"), (mass, "d"), (role, "B"),
    ]:
        f.write(struct.pack("<%d%s" % (n, fmt), *arr))
print(f"[0491g-state] state={state_path} cells={nx*ny} fluid={n} gamma={gamma} mass_ratio={liquid_mass/gas_mass:.17g}")
PY_STATE_0491G

species_block_0491g() {
  awk -v g="$GAMMA" -v mg="$GAS_PARTICLE_MASS" -v ml="$LIQUID_PARTICLE_MASS" 'BEGIN {
    printf "speciesRegistryEnable = true\n";
    printf "speciesCount = 3\n";
    printf "species0 = 0 gas_compressible_default gas 0.0 0.0 %.17g\n", g*mg;
    printf "species1 = 1 liquid_incompressible liquid 1.0 1.0 %.17g\n", g*ml;
    printf "species2 = 2 gas_compressible gas 0.0 0.0 %.17g\n", g*mg;
  }'
}

write_params_0491g() {
  local case_dir=$1
  local case_name=$2
  local params="$case_dir/params/species_q6_boundary_darcy_0491g.kv"
  mkdir -p "$case_dir/params" "$case_dir/output" "$case_dir/logs"
  cat > "$params" <<PARAMS_0491G_COMMON
inputState = $STATE
outputDir = $case_dir/output
Lx = 1.0
Ly = 1.0
Nx = $NX
Ny = $NY
dt = $DT
nSteps = $STEPS
srcClassicCudaModeEnable = false
projectionEnable = true
projectionBackend = cuda
projectionOperator = auto_fv_cg
projectionMaxIterations = 250
projectionTolerance = 1.0e-12
projectionMomentumCorrectionEnable = true
q6ProjectionStrength = 1.0
resamplingEnable = false
closedCapacityResponseEnable = false
closedCapacityVirialKickEnable = false
keepMeanFlowEnable = false
rotationAngle = 2.0943951023931953
randomRotationSign = true
gridShiftEnable = true
rngSeed = $SEED
thermostatEnable = false
kBT = $KBT
summaryEvery = $SUMMARY_EVERY
dumpStateEvery = 0
summaryRoleFilter = fluid
dumpRoleFilter = fluid
initialInactiveSlots = 128
numThreads = 4
$(species_block_0491g)
speciesRequireRegisteredTypes = true
speciesDiagnosticsEnable = true
speciesDiagnosticsFilename = species_runtime_0491g.csv
speciesCellDiagnosticsEnable = false
speciesQ6Enable = true
speciesQ6Mode = weighted
speciesQ6Sensitivity = 1.0
speciesQ6FallbackMode = common
speciesQ6ComparisonTolerance = $SPECIES_Q6_COMPARISON_TOLERANCE
PARAMS_0491G_COMMON

  case "$case_name" in
    periodic)
      cat >> "$params" <<'PARAMS_0491G_PERIODIC'
bcLeft = periodic
bcRight = periodic
bcBottom = periodic
bcTop = periodic
bcX = periodic
bcY = periodic
PARAMS_0491G_PERIODIC
      ;;
    channel_wall|darcy_channel)
      cat >> "$params" <<'PARAMS_0491G_WALL'
bcLeft = periodic
bcRight = periodic
bcBottom = solid
bcTop = solid
bcX = periodic
bcY = wall
wallAccommodation = 1.0
wallThermalNoise = 0.0
wallKBT = -1.0
wallVpGamma = 4
wallVpMass = 1.0
PARAMS_0491G_WALL
      ;;
    io_fullface)
      cat >> "$params" <<PARAMS_0491G_FULLFACE
bcLeft = inlet
bcRight = outlet
bcBottom = solid
bcTop = solid
bcX = open
bcY = wall
inletUxLeft = $UIN
inletUyLeft = 0.0
inletReservoirMode = hard_cell_density
inletInjectionMode = hard_cell_density
inletReservoirCells = 1
inletTargetOccupancy = $GAMMA
inletVelocitySpatialProfile = uniform
inletThermalNoise = 0.0
inletKBT = -1.0
openBoundaryOutletMode = balanced_flux
wallAccommodation = 1.0
wallThermalNoise = 0.0
wallKBT = -1.0
wallVpGamma = 4
wallVpMass = 1.0
PARAMS_0491G_FULLFACE
      ;;
    io_segmented_injection)
      cat >> "$params" <<PARAMS_0491G_SEGMENTED
bcLeft = solid
bcRight = solid
bcBottom = solid
bcTop = solid
bcX = wall
bcY = wall
openBoundarySegmentsEnable = true
openBoundarySegmentCount = 2
openBoundarySegment0 = left inlet 0.25 0.75 $UIN 0.0 1 $LIQUID_PARTICLE_MASS
openBoundarySegment1 = right outlet 0.00 1.00 $UIN 0.0 0 $GAS_PARTICLE_MASS
inletReservoirMode = hard_cell_density
inletInjectionMode = hard_cell_density
inletReservoirCells = 1
inletTargetOccupancy = $GAMMA
inletVelocitySpatialProfile = uniform
inletThermalNoise = 0.0
inletKBT = -1.0
openBoundaryOutletMode = hybrid
wallAccommodation = 1.0
wallThermalNoise = 0.0
wallKBT = -1.0
wallVpGamma = 4
wallVpMass = 1.0
PARAMS_0491G_SEGMENTED
      ;;
    *)
      echo "[0491g] internal error: unknown case $case_name" >&2
      return 2
      ;;
  esac

  if [[ "$case_name" == "darcy_channel" ]]; then
    cat >> "$params" <<'PARAMS_0491G_DARCY'
darcyBrinkmanEnable = true
darcyChiMode = circle
darcyCircleCx = 0.5
darcyCircleCy = 0.5
darcyCircleR = 0.35
darcyInterfaceWidth = 0.0
darcyAlphaMin = 0.0
darcyAlphaMax = 1.0
darcyQ = 0.5
darcyUSolidX = 0.0
darcyUSolidY = 0.0
darcyBrinkmanForcingMode = mean
darcyCostEvery = 1
darcyCostFilename = darcy_cost_0343.csv
PARAMS_0491G_DARCY
  fi
}

run_case_0491g() {
  local case_name=$1
  local expected_family=$2
  local expected_open=$3
  local expected_darcy=$4
  local expected_injection_type=$5
  local case_dir="$RUN_ROOT/$case_name"
  local log="$case_dir/logs/species_q6_boundary_darcy_0491g.log"
  local env_log="$case_dir/logs/environment_0491g.env"
  write_params_0491g "$case_dir" "$case_name" || return 2

  suite_clear_cuda_flags_0434
  export MPCD_CUDA_INACTIVE_TAIL_POOL_0313=1
  export MPCD_CUDA_PERSISTENT_PARTICLE_STATE_USE=1
  export MPCD_CUDA_PERSISTENT_PARTICLE_METADATA_CACHE=1
  export MPCD_CUDA_PERSISTENT_CELL_WORKSPACE_USE=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_STRICT=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251_STRICT=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_ACTIVE_STRICT=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_MINIMAL_DOWNLOAD_0257=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_DEVICE_ROTATION_0272=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_FAST_THERMOSTAT_DIAG_0321=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_FUSED_STREAM_DEPOSIT_0274=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WORKSPACE_DOWNLOAD_0272=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_HOST_CELLID_FILL_0327=1
  export MPCD_CUDA_Q6_RESIDENT_0400=1
  export MPCD_CUDA_Q6_RESIDENT_STRICT_0400=1
  export MPCD_CUDA_Q6_RESIDENT_THERMOSTAT_0400=0

  case "$case_name" in
    periodic)
      export MPCD_CUDA_STREAMING_PERIODIC_0245=1
      export MPCD_CUDA_CLASSIC_SRC_PERIODIC_RESIDENT_0260=1
      export MPCD_CUDA_Q6_RESIDENT_SRC_STEP_0401=1
      ;;
    channel_wall|darcy_channel)
      export MPCD_CUDA_STREAMING_WALL_SIMPLE_0246=1
      export MPCD_CUDA_CLASSIC_SRC_WALL_RESIDENT_0261=1
      export MPCD_CUDA_PERSISTENT_SRC_COLLISION_WALL_SIMPLE_0253=1
      export MPCD_CUDA_Q6_RESIDENT_SRC_WALL_STEP_0402=1
      ;;
    io_fullface)
      export MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263=1
      export MPCD_CUDA_Q6_RESIDENT_SRC_IO_FULLFACE_0404=1
      ;;
    io_segmented_injection)
      export MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264=1
      export MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264_STRICT=1
      export MPCD_CUDA_INLET_OUTLET_SEGMENTED_0249B=1
      export MPCD_CUDA_Q6_RESIDENT_SRC_IO_SEGMENTED_0409=1
      ;;
  esac

  export MPCD_DISABLED_RESAMPLING_SUMMARY_DIAGNOSTICS_0315G=0
  export SRC_LIVE_VIS_ENABLE=0
  export MPCD_LIVE_VIS_ENABLE=0

  env | sort | grep -E '^(MPCD_CUDA|MPCD_DISABLED_RESAMPLING|SRC_LIVE_VIS|MPCD_LIVE_VIS)' > "$env_log"
  echo "[0491g] case=$case_name family=$expected_family open=$expected_open darcy=$expected_darcy injectType=$expected_injection_type"
  set +e
  /usr/bin/time -p "$BIN" "$case_dir/params/species_q6_boundary_darcy_0491g.kv" > "$log" 2>&1
  local rc=$?
  set -e
  echo "$case_name,$rc,$expected_family,$expected_open,$expected_darcy,$expected_injection_type" >> "$RUN_ROOT/launch_status_0491g.csv"
  return 0
}

echo "case,exit_code,expected_boundary_family,expected_open,expected_darcy,expected_injection_type" > "$RUN_ROOT/launch_status_0491g.csv"
run_case_0491g periodic periodic 0 0 none
run_case_0491g channel_wall channel_wall 0 0 none
run_case_0491g io_fullface open_fullface 1 0 none
run_case_0491g io_segmented_injection open_segmented 1 0 1
run_case_0491g darcy_channel channel_wall 0 1 none

python3 scripts/summarize_0491g_species_q6_boundary_darcy_matrix.py \
  --root "$RUN_ROOT" \
  --expected-steps "$STEPS" \
  --csv "$RUN_ROOT/species_q6_boundary_darcy_0491g.csv" \
  --markdown "$RUN_ROOT/species_q6_boundary_darcy_0491g.md"

echo "[0491g] audit=$RUN_ROOT/species_q6_boundary_darcy_0491g.csv"
echo "[0491g] report=$RUN_ROOT/species_q6_boundary_darcy_0491g.md"
