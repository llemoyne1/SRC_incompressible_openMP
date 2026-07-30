#!/usr/bin/env bash
set -uo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434

BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}"
RUN_ROOT="${RUN_ROOT:-runs/0493w7_independent_masked_multibc_smoke}"
NX="${NX:-8}"
NY="${NY:-6}"
GAMMA="${GAMMA:-4}"
STEPS="${STEPS:-2}"
DT="${DT:-0.01}"
KBT="${KBT:-0.005}"
SEED="${SEED:-49307}"
UIN="${UIN:-0.02}"
MIN_OCC="${MIN_OCC:-0.5}"
LIQUID_MASS="${LIQUID_MASS:-10.0}"
GAS_MASS="${GAS_MASS:-1.0}"
LIQUID_PER_CELL="${LIQUID_PER_CELL:-$(((3 * GAMMA + 3) / 4))}"
UOUT="$(awk -v u="$UIN" 'BEGIN{printf "%.17g", 0.5*u}')"

if (( GAMMA < 3 || LIQUID_PER_CELL <= GAMMA / 2 || LIQUID_PER_CELL >= GAMMA )); then
  echo "[0493w7] ERROR require GAMMA>=3 and GAMMA/2 < LIQUID_PER_CELL < GAMMA" >&2
  exit 2
fi

rm -rf "$RUN_ROOT"
mkdir -p "$RUN_ROOT/init" "$RUN_ROOT/logs"
suite_ensure_binary_0434

STATE="$RUN_ROOT/init/independent_masked_multibc_0493w7.smpcd"
python3 - "$STATE" "$NX" "$NY" "$GAMMA" "$LIQUID_PER_CELL" "$LIQUID_MASS" "$GAS_MASS" <<'PY_STATE'
import math
import os
import struct
import sys

path, nx, ny, gamma, nliq, ml, mg = sys.argv[1:]
nx, ny, gamma, nliq = map(int, (nx, ny, gamma, nliq))
ml, mg = float(ml), float(mg)
x=[]; y=[]; vx=[]; vy=[]; typ=[]; mass=[]; role=[]
for j in range(ny):
    for i in range(nx):
        xc=(i+0.5)/nx; yc=(j+0.5)/ny
        ux=0.025*math.sin(2*math.pi*xc)*math.cos(2*math.pi*yc)
        uy=0.018*math.cos(2*math.pi*xc)*math.sin(2*math.pi*yc)
        for k in range(gamma):
            x.append((i+(k+0.5)/gamma)/nx)
            y.append((j+(((3*k+1)%gamma)+0.5)/gamma)/ny)
            vx.append(ux); vy.append(uy)
            liquid = k < nliq
            typ.append(1 if liquid else 2)
            mass.append(ml if liquid else mg)
            role.append(1)
os.makedirs(os.path.dirname(path), exist_ok=True)
magic=b"SRCMPCD_STATE"+b"\0"*(16-len("SRCMPCD_STATE"))
reserved=[0]*8; reserved[0]=1; reserved[1]=1
with open(path,"wb") as f:
    f.write(magic)
    f.write(struct.pack("<IIIIQIIII",2,0x01020304,2,1,len(x),1,1,8,4))
    f.write(struct.pack("<8Q",*reserved))
    for arr,fmt in [(x,"d"),(y,"d"),(vx,"d"),(vy,"d"),(typ,"I"),(mass,"d"),(role,"B")]:
        f.write(struct.pack(f"<{len(arr)}{fmt}",*arr))
print(f"[0493w7-state] state={path} cells={nx*ny} liquid/cell={nliq} gas/cell={gamma-nliq}")
PY_STATE

write_params() {
  local case_name=$1
  local case_dir="$RUN_ROOT/$case_name"
  local params="$case_dir/params/independent_masked_multibc_0493w7.kv"
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
srcClassicCudaModeEnable = false
projectionEnable = true
projectionBackend = cuda
projectionOperator = auto_fv_cg
projectionMaxIterations = 300
projectionTolerance = 1.0e-11
projectionMomentumCorrectionEnable = false
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
summaryEvery = 1
dumpStateEvery = 0
summaryRoleFilter = fluid
dumpRoleFilter = fluid
initialInactiveSlots = 256
numThreads = 4
speciesRegistryEnable = true
speciesCount = 2
species0 = 1 liquid_incompressible liquid 1.0 1.0 $(awk -v g="$GAMMA" -v m="$LIQUID_MASS" 'BEGIN{printf "%.17g",g*m}')
species1 = 2 gas_compressible gas 0.0 0.0 $(awk -v g="$GAMMA" -v m="$GAS_MASS" 'BEGIN{printf "%.17g",g*m}')
speciesRequireRegisteredTypes = true
speciesDiagnosticsEnable = true
speciesDiagnosticsFilename = species_runtime_0493w7.csv
speciesCellDiagnosticsEnable = false
speciesQ6Enable = true
speciesQ6Mode = independent_masked
speciesQ6Sensitivity = 1.0
speciesQ6FallbackMode = common
speciesQ6MinOccupancyFraction = $MIN_OCC
PARAMS

  case "$case_name" in
    periodic)
      cat >> "$params" <<'PARAMS'
bcLeft = periodic
bcRight = periodic
bcBottom = periodic
bcTop = periodic
bcX = periodic
bcY = periodic
PARAMS
      ;;
    channel_wall|darcy_channel)
      cat >> "$params" <<'PARAMS'
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
PARAMS
      ;;
    io_fullface)
      cat >> "$params" <<PARAMS
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
PARAMS
      ;;
    io_segmented)
      cat >> "$params" <<PARAMS
bcLeft = solid
bcRight = solid
bcBottom = solid
bcTop = solid
bcX = wall
bcY = wall
openBoundarySegmentsEnable = true
openBoundarySegmentCount = 2
openBoundarySegment0 = left inlet 0.25 0.75 $UIN 0.0 1 $LIQUID_MASS
openBoundarySegment1 = right outlet 0.00 1.00 $UOUT 0.0 0 $GAS_MASS
inletReservoirMode = hard_cell_density
inletInjectionMode = hard_cell_density
inletReservoirCells = 1
inletTargetOccupancy = $GAMMA
inletVelocitySpatialProfile = uniform
inletThermalNoise = 0.0
inletKBT = -1.0
openBoundaryOutletMode = hybrid
openBoundaryOutletHybridBlend = 0.0
openBoundaryOutletFeedbackGain = 0.0
wallAccommodation = 1.0
wallThermalNoise = 0.0
wallKBT = -1.0
wallVpGamma = 4
wallVpMass = 1.0
PARAMS
      ;;
  esac

  if [[ "$case_name" == darcy_channel ]]; then
    cat >> "$params" <<'PARAMS'
darcyBrinkmanEnable = true
darcyChiMode = circle
darcyCircleCx = 0.5
darcyCircleCy = 0.5
darcyCircleR = 0.25
darcyInterfaceWidth = 0.0
darcyAlphaMin = 0.0
darcyAlphaMax = 1.0
darcyQ = 0.5
darcyUSolidX = 0.0
darcyUSolidY = 0.0
darcyBrinkmanForcingMode = mean
darcyCostEvery = 1
darcyCostFilename = darcy_cost_0343.csv
PARAMS
  fi
}

run_case() {
  local case_name=$1 family=$2 open=$3 darcy=$4
  local case_dir="$RUN_ROOT/$case_name"
  local log="$case_dir/logs/independent_masked_multibc_0493w7.log"
  write_params "$case_name"
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
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_FUSED_STREAM_DEPOSIT_0274=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WORKSPACE_DOWNLOAD_0272=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_HOST_CELLID_FILL_0327=1
  export MPCD_CUDA_Q6_RESIDENT_0400=1
  export MPCD_CUDA_Q6_RESIDENT_STRICT_0400=1
  export MPCD_CUDA_Q6_RESIDENT_THERMOSTAT_0400=0
  export LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
  export SRC_LIVE_VIS_ENABLE=0
  export MPCD_LIVE_VIS_ENABLE=0

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
    io_segmented)
      export MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264=1
      export MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264_STRICT=1
      export MPCD_CUDA_INLET_OUTLET_SEGMENTED_0249B=1
      export MPCD_CUDA_Q6_RESIDENT_SRC_IO_SEGMENTED_0409=1
      ;;
  esac

  echo "[0493w7] case=$case_name family=$family open=$open darcy=$darcy"
  set +e
  /usr/bin/time -p "$BIN" "$case_dir/params/independent_masked_multibc_0493w7.kv" > "$log" 2>&1
  local rc=$?
  set -e
  echo "$case_name,$rc,$family,$open,$darcy" >> "$RUN_ROOT/launch_status_0493w7.csv"
}

echo "case,exit_code,expected_boundary_family,expected_open,expected_darcy" > "$RUN_ROOT/launch_status_0493w7.csv"
run_case periodic periodic 0 0
run_case channel_wall channel_wall 0 0
run_case io_fullface open_fullface 1 0
run_case io_segmented open_segmented 1 0
run_case darcy_channel channel_wall 0 1

python3 scripts/check_0493w7_independent_masked_multibc.py \
  --root "$RUN_ROOT" --expected-steps "$STEPS"
