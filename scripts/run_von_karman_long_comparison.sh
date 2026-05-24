#!/usr/bin/env bash
set -euo pipefail

# Long periodic-cylinder comparison inspired by the CUDA VK case.
# This is deliberately not an inlet/outlet case yet: the current OpenMP Q6/Q9
# projector is still validated for periodic/channel external boundaries.  We
# impose a CUDA-like global mean flow in a periodic box and compare classic vs
# full liquid closure on the same fixed immersed circle.

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

BIN="${BIN:-./build/src_mpcd_base}"
STATE="${STATE:-initial_state_von_karman_320x64_g20.smpcd}"
CONFIG_DIR="${CONFIG_DIR:-runs/von_karman_long_configs}"
mkdir -p "$CONFIG_DIR"

Lx="${Lx:-2.0}"
Ly="${Ly:-0.4}"
Nx="${Nx:-320}"
Ny="${Ny:-64}"
GAMMA="${GAMMA:-20}"
KBT="${KBT:-0.0025}"
DT="${DT:-0.001}"
N_STEPS="${N_STEPS:-5000}"
DUMP_EVERY="${DUMP_EVERY:-10}"
SUMMARY_EVERY="${SUMMARY_EVERY:-500}"


THREADS="${THREADS:-${NUM_THREADS:-18}}"
export OMP_NUM_THREADS="$THREADS"
export OMP_DYNAMIC=FALSE
export OMP_PROC_BIND="${OMP_PROC_BIND:-spread}"
export OMP_PLACES="${OMP_PLACES:-cores}"

echo "[von-karman] THREADS=$THREADS OMP_NUM_THREADS=$OMP_NUM_THREADS OMP_DYNAMIC=$OMP_DYNAMIC"

SEED="${SEED:-12345}"
U0="${U0:-0.9}"
CX="${CX:-0.35}"
CY="${CY:-0.20}"
R="${R:-0.04}"
ALPHA_DEG="${ALPHA_DEG:-90}"

RUN_CLASSIC="${RUN_CLASSIC:-0}"
RUN_LIQUID="${RUN_LIQUID:-1}"
RUN_ANALYSIS="${RUN_ANALYSIS:-0}"

if [[ ! -x "$BIN" ]]; then
  echo "[von-karman] missing binary $BIN; build first with ./scripts/build_src_mpcd_base.sh" >&2
  exit 1
fi

if [[ ! -f "$STATE" ]]; then
  echo "[von-karman] generating initial state $STATE"
  matlab -batch "cd('matlab'); generate_von_karman_cylinder_state('output','../$STATE','Lx',$Lx,'Ly',$Ly,'Nx',$Nx,'Ny',$Ny,'gamma',$GAMMA,'kBT',$KBT,'seed',$SEED,'circleCx',$CX,'circleCy',$CY,'circleR',$R);"
fi

write_common() {
  local out="$1"
  local method="$2"
  local output_dir="$3"
  cat > "$out" <<KV
inputState = $STATE
outputDir = $output_dir

Lx = $Lx
Ly = $Ly
Nx = $Nx
Ny = $Ny

dt = $DT
nSteps = $N_STEPS

alphaDeg = $ALPHA_DEG
randomRotationSign = true
gridShiftEnable = true
rngSeed = $SEED

bcLeft = periodic
bcRight = periodic
bcBottom = periodic
bcTop = periodic

bodyAccelerationX = 0.0
bodyAccelerationY = 0.0
keepMeanFlowEnable = true
targetMeanUx = $U0
targetMeanUy = 0.0

immersedSolidEnable = true
immersedSolidShape = circle
immersedSolidCx = $CX
immersedSolidCy = $CY
immersedSolidR = $R
immersedSolidFractionSamples = 6
immersedSolidWallUx = 0.0
immersedSolidWallUy = 0.0
immersedSolidOmega = 0.0

wallAccommodation = 1.0
wallVpGamma = 0.0
wallVpMass = 1.0
wallKBT = -1.0
wallThermalNoise = 1.0

thermostatEnable = true
thermostatMode = cell_relative_rescale
thermostatEvery = 1
thermostatTargetKBT = -1.0
thermostatMinParticles = 3
kBT = $KBT

method = $method
projectionOperator = elliptic_fv_cg
projectionMaxIterations = 600
projectionTolerance = 1.0e-10
projectionMomentumCorrectionEnable = true
q6ProjectionStrength = 0.50
projectionImmersedSolidMaskEnable = true
projectionImmersedSolidFluidFractionThreshold = 0.5

q9MassFluxProjectionEnable = false
q9MassFluxProjectionStrength = 1.0
q9DensityRelaxationBeta = 0.001
q9TargetFilter = elliptic_lowpass
q9LowKMaxIndex = 4
q9EllipticLowPassPasses = 1
q9MomentumCorrectionEnable = true

virialDiagnosticsEnable = false
virialKickEnable = false
Kvirial = 0.0
virialBeta = 0.0
virialRhoEOSRefMode = initial_physical_density
virialRhoUniformMode = reference_gamma_current_volume
virialDriveTargetMode = current_uniform
virialRhoKickMode = uniform_now
virialRhoKickMinFraction = 0.1
virialMomentumCorrectionEnable = true

summaryEvery = $SUMMARY_EVERY
dumpStateEvery = $DUMP_EVERY
numThreads = $THREADS
KV
}

classic_cfg="$CONFIG_DIR/params_von_karman_classic_320x64.kv"
liquid_cfg="$CONFIG_DIR/params_von_karman_q9_virial_320x64.kv"

write_common "$classic_cfg" "classic" "runs/von_karman_classic_long_320x64"
# Disable the mask for the classic config; it is unused by classic and avoids confusion in params_used.kv.
sed -i 's/projectionImmersedSolidMaskEnable = true/projectionImmersedSolidMaskEnable = false/' "$classic_cfg"

write_common "$liquid_cfg" "q9_virial" "runs/von_karman_q9_virial_long_320x64"
# Enable final liquid closure settings.
sed -i 's/q9MassFluxProjectionEnable = false/q9MassFluxProjectionEnable = true/' "$liquid_cfg"
sed -i 's/virialDiagnosticsEnable = false/virialDiagnosticsEnable = true/' "$liquid_cfg"
sed -i 's/virialKickEnable = false/virialKickEnable = true/' "$liquid_cfg"
sed -i 's/Kvirial = 0.0/Kvirial = 0.50/' "$liquid_cfg"
sed -i 's/virialBeta = 0.0/virialBeta = 0.05/' "$liquid_cfg"

if [[ "$RUN_CLASSIC" != "0" ]]; then
  echo "[von-karman] running classic: $classic_cfg"
  "$BIN" "$classic_cfg"
fi

if [[ "$RUN_LIQUID" != "0" ]]; then
  echo "[von-karman] running q9_virial full liquid closure: $liquid_cfg"
  "$BIN" "$liquid_cfg"
fi

if [[ "$RUN_ANALYSIS" != "0" ]]; then
  matlab -batch "cd('matlab'); validate_von_karman_long_comparison();"
fi
