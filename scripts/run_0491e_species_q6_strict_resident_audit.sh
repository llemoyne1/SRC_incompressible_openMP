#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434

BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_0400}"
RUN_ROOT="${RUN_ROOT:-runs/0491e_species_q6_strict_resident}"
NX="${NX:-8}"
NY="${NY:-4}"
GAMMA="${GAMMA:-4}"
STEPS="${STEPS:-2}"
SUMMARY_EVERY="${SUMMARY_EVERY:-1}"
DT="${DT:-0.01}"
KBT="${KBT:-0.005}"
SEED="${SEED:-49105}"
LIQUID_TO_GAS_MASS_RATIO="${LIQUID_TO_GAS_MASS_RATIO:-10.0}"
GAS_PARTICLE_MASS="${GAS_PARTICLE_MASS:-1.0}"
LIQUID_PARTICLE_MASS="${LIQUID_PARTICLE_MASS:-$(awk -v mg="$GAS_PARTICLE_MASS" -v r="$LIQUID_TO_GAS_MASS_RATIO" 'BEGIN{printf "%.17g", mg*r}')}"
SPECIES_Q6_COMPARISON_TOLERANCE="${SPECIES_Q6_COMPARISON_TOLERANCE:-1.0e-11}"

if (( GAMMA < 2 )); then
  echo "[0491e] ERROR GAMMA must be >=2 to seed both species in every cell" >&2
  exit 2
fi

if [[ "${CLEAN_RUN_ROOT:-1}" == 1 ]]; then
  rm -rf "$RUN_ROOT"
fi
mkdir -p "$RUN_ROOT/init" "$RUN_ROOT/params" "$RUN_ROOT/output" "$RUN_ROOT/logs"

suite_ensure_binary_0434

STATE="$RUN_ROOT/init/species_q6_strict_resident_0491e.smpcd"
PARAMS="$RUN_ROOT/params/species_q6_strict_resident_0491e.kv"
LOG="$RUN_ROOT/logs/species_q6_strict_resident_0491e.log"
TIME_LOG="$RUN_ROOT/logs/species_q6_strict_resident_0491e.time"
ENV_LOG="$RUN_ROOT/logs/environment_0491e.env"

python3 - "$STATE" "$NX" "$NY" "$GAMMA" "$GAS_PARTICLE_MASS" "$LIQUID_PARTICLE_MASS" "$SEED" <<'PY_STATE_0491E'
import math
import os
import random
import struct
import sys

state_path, nx, ny, gamma, gas_mass, liquid_mass, seed = sys.argv[1:]
nx, ny, gamma, seed = int(nx), int(ny), int(gamma), int(seed)
gas_mass, liquid_mass = float(gas_mass), float(liquid_mass)
random.seed(seed)

x = []
y = []
vx = []
vy = []
typ = []
mass = []
role = []

for j in range(ny):
    for i in range(nx):
        for k in range(gamma):
            frac = (k + 0.5) / gamma
            px = (i + frac) / nx
            py = (j + ((k * 3 + 1) % gamma + 0.5) / gamma) / ny
            angle = 2.0 * math.pi * (px + 0.5 * py)
            x.append(px)
            y.append(py)
            vx.append(0.03 * math.sin(angle))
            vy.append(0.02 * math.cos(2.0 * math.pi * (py - px)))
            if k == 0:
                typ.append(1)
                mass.append(liquid_mass)
            else:
                typ.append(2)
                mass.append(gas_mass)
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
print(f"[0491e-state] state={state_path} cells={nx*ny} fluid={n} gamma={gamma} mass_ratio={liquid_mass/gas_mass:.17g}")
PY_STATE_0491E

cat > "$PARAMS" <<PARAMS_0491E
inputState = $STATE
outputDir = $RUN_ROOT/output
Lx = 1.0
Ly = 1.0
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
srcClassicCudaModeEnable = false
projectionEnable = true
projectionBackend = cuda
projectionOperator = auto_fv_cg
projectionMaxIterations = 200
projectionTolerance = 1.0e-12
projectionMomentumCorrectionEnable = true
q6ProjectionStrength = 1.0
resamplingEnable = false
closedCapacityResponseEnable = false
closedCapacityVirialKickEnable = false
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
initialInactiveSlots = 0
numThreads = 4
speciesRegistryEnable = true
speciesCount = 2
species0 = 1 liquid_incompressible liquid 1.0 1.0 $(awk -v g="$GAMMA" -v m="$LIQUID_PARTICLE_MASS" 'BEGIN{printf "%.17g", g*m}')
species1 = 2 gas_compressible gas 0.0 0.0 $(awk -v g="$GAMMA" -v m="$GAS_PARTICLE_MASS" 'BEGIN{printf "%.17g", g*m}')
speciesRequireRegisteredTypes = true
speciesDiagnosticsEnable = true
speciesDiagnosticsFilename = species_runtime_0491e.csv
speciesCellDiagnosticsEnable = false
speciesQ6Enable = true
speciesQ6Mode = weighted
speciesQ6Sensitivity = 1.0
speciesQ6FallbackMode = common
speciesQ6ComparisonTolerance = $SPECIES_Q6_COMPARISON_TOLERANCE
PARAMS_0491E

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
export MPCD_CUDA_STREAMING_PERIODIC_0245=1
export MPCD_CUDA_CLASSIC_SRC_PERIODIC_RESIDENT_0260=1
export MPCD_CUDA_Q6_RESIDENT_SRC_STEP_0401=1
export MPCD_CUDA_Q6_RESIDENT_0400=1
export MPCD_CUDA_Q6_RESIDENT_STRICT_0400=1
export MPCD_CUDA_Q6_RESIDENT_THERMOSTAT_0400=0
export MPCD_DISABLED_RESAMPLING_SUMMARY_DIAGNOSTICS_0315G=0
export SRC_LIVE_VIS_ENABLE=0
export MPCD_LIVE_VIS_ENABLE=0

env | sort | grep -E '^(MPCD_CUDA|MPCD_DISABLED_RESAMPLING|SRC_LIVE_VIS|MPCD_LIVE_VIS)' > "$ENV_LOG"

echo "[0491e] run root=$RUN_ROOT bin=$BIN grid=${NX}x${NY} gamma=$GAMMA steps=$STEPS"
/usr/bin/time -p "$BIN" "$PARAMS" > "$LOG" 2>&1
cp "$LOG" "$TIME_LOG"

python3 scripts/summarize_0491e_species_q6_strict_resident.py \
  --run-root "$RUN_ROOT" \
  --expected-steps "$STEPS" \
  --csv "$RUN_ROOT/species_q6_strict_resident_0491e.csv" \
  --markdown "$RUN_ROOT/species_q6_strict_resident_0491e.md"

echo "[0491e] audit=$RUN_ROOT/species_q6_strict_resident_0491e.csv"
echo "[0491e] report=$RUN_ROOT/species_q6_strict_resident_0491e.md"
