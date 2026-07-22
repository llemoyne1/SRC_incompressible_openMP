#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_0400}"
RUN_ROOT="${RUN_ROOT:-runs/0490a_species_registry_smoke}"
NX="${NX:-80}"
NY="${NY:-20}"
GAMMA="${GAMMA:-4}"
STEPS="${STEPS:-20}"
SUMMARY_EVERY="${SUMMARY_EVERY:-5}"
SEED="${SEED:-1628490}"

rm -rf "$RUN_ROOT"
mkdir -p "$RUN_ROOT/init" "$RUN_ROOT/output" "$RUN_ROOT/logs"

STATE="$RUN_ROOT/init/type2_background.smpcd"
PARAMS="$RUN_ROOT/params_0490a.kv"
LOG="$RUN_ROOT/logs/run.log"

python3 scripts/src_mpcd_case_generator_0434.py \
  --case injection --state "$STATE" \
  --Lx 4.0 --Ly 1.0 --Nx "$NX" --Ny "$NY" --gamma "$GAMMA" \
  --kBT 0.01 --mass 1.0 --seed "$SEED" --u0 0.0 \
  --velocity-mode zero --background-type 2 --inactive-type 0 \
  --inactive-slots $((NX * NY * GAMMA))

cat > "$PARAMS" <<PARAMS
inputState = $STATE
outputDir = $RUN_ROOT/output
Lx = 4.0
Ly = 1.0
Nx = $NX
Ny = $NY
dt = 0.005
nSteps = $STEPS
bcLeft = solid
bcRight = solid
bcBottom = solid
bcTop = solid
openBoundarySegmentsEnable = true
openBoundarySegmentCount = 2
openBoundarySegment0 = left inlet 0.40 0.60 0.50 0.0 1 1.0
openBoundarySegment1 = right outlet 0.0 1.0 0.0 0.0 0 1.0
inletInjectionMode = hard_cell_density
inletReservoirMode = hard_cell_density
inletReservoirCells = 1
inletTargetOccupancy = $GAMMA
inletVelocityRampEnable = false
inletKBT = 0.01
inletThermalNoise = 0.0
inletRandomizeTangential = true
inletReinjectBackflow = true
openBoundaryOutletMode = neumann
wallAccommodation = 1.0
wallVpGamma = $GAMMA
wallVpMass = 1.0
wallKBT = 0.01
wallThermalNoise = 0.0
srcClassicCudaModeEnable = true
projectionEnable = false
projectionBackend = cpu
resamplingEnable = false
rotationAngle = 2.0943951023931953
randomRotationSign = true
gridShiftEnable = true
rngSeed = $SEED
thermostatEnable = false
kBT = 0.01
summaryEvery = $SUMMARY_EVERY
dumpStateEvery = 0
summaryRoleFilter = fluid
dumpRoleFilter = fluid
numThreads = 4
speciesRegistryEnable = true
speciesCount = 2
species0 = 1 injected_liquid liquid 1.0 1.0
species1 = 2 background_gas gas 0.0 0.0
speciesRequireRegisteredTypes = true
speciesDiagnosticsEnable = true
speciesDiagnosticsFilename = species_runtime_0490a.csv
PARAMS

export SRC_LIVE_VIS_ENABLE=0
export MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264=1
export MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264_STRICT=1
export MPCD_CUDA_INLET_OUTLET_SEGMENTED_0249B=1
export MPCD_CUDA_PERSISTENT_PARTICLE_STATE_USE=1
export MPCD_CUDA_PERSISTENT_CELL_WORKSPACE_USE=1
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=1
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251=1
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_STRICT=1
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251_STRICT=1
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_ACTIVE_STRICT=1
export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE=0

[[ -x "$BIN" ]] || {
  echo "[0490a] ERROR missing binary: $BIN" >&2
  echo "[0490a] Build first with scripts/build_src_mpcd_cuda_q6_resident_0400.sh" >&2
  exit 127
}

"$BIN" "$PARAMS" | tee "$LOG"

CSV="$RUN_ROOT/output/species_runtime_0490a.csv"
[[ -s "$CSV" ]] || { echo "[0490a] ERROR missing species CSV: $CSV" >&2; exit 3; }

python3 - "$CSV" <<'PY'
import csv
import math
import sys
from collections import defaultdict

path = sys.argv[1]
rows = list(csv.DictReader(open(path, newline="")))
if not rows:
    raise SystemExit("[0490a] FAIL: empty species diagnostics")

by_type = defaultdict(list)
for row in rows:
    by_type[int(row["type"])].append(row)

if set(by_type) != {1, 2}:
    raise SystemExit(f"[0490a] FAIL: expected registered types {{1,2}}, got {sorted(by_type)}")
if any(int(row["registered"]) != 1 for row in rows):
    raise SystemExit("[0490a] FAIL: unregistered transported type reported")
if any(row["phaseFamily"] not in {"liquid", "gas"} for row in rows):
    raise SystemExit("[0490a] FAIL: invalid phase family")

initial_type2 = float(by_type[2][0]["totalMass"])
final_type2 = float(by_type[2][-1]["totalMass"])
final_type1 = float(by_type[1][-1]["totalMass"])
if initial_type2 <= 0.0:
    raise SystemExit("[0490a] FAIL: background type 2 has no initial mass")
if final_type1 <= 0.0:
    raise SystemExit("[0490a] FAIL: injected type 1 was not observed")
if not all(math.isfinite(float(row["totalMass"])) for row in rows):
    raise SystemExit("[0490a] FAIL: non-finite species mass")

print("[0490a] PASS")
print(f"[0490a] rows={len(rows)} types={sorted(by_type)}")
print(f"[0490a] type1_final_mass={final_type1:.17g}")
print(f"[0490a] type2_initial_mass={initial_type2:.17g}")
print(f"[0490a] type2_final_mass={final_type2:.17g}")
PY

echo "[0490a] CSV=$CSV"
echo "[0490a] LOG=$LOG"
