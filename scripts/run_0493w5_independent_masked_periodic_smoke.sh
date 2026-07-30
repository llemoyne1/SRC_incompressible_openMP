#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434

BIN="${BIN:-${SRC_MPCD_DEFAULT_BIN_0434:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}}"
RUN_ROOT="${RUN_ROOT:-runs/0493w5_independent_masked_periodic_smoke}"
NX="${NX:-16}"
NY="${NY:-12}"
GAMMA="${GAMMA:-10}"
STEPS="${STEPS:-1}"
MIN_OCC="${MIN_OCC:-0.5}"
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"

if [[ "$CLEAN_RUN_ROOT" == 1 ]]; then rm -rf "$RUN_ROOT"; fi
mkdir -p "$RUN_ROOT/states" "$RUN_ROOT/logs"
suite_ensure_binary_0434

write_params() {
  local profile=$1 state=$2 out=$3 params=$4
  mkdir -p "$out" "$(dirname "$params")"
  cat > "$params" <<PARAMS
inputState = $state
outputDir = $out
Lx = 1.0
Ly = 1.0
Nx = $NX
Ny = $NY
dt = 0.001
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
projectionMaxIterations = 1000
projectionTolerance = 1.0e-10
projectionMomentumCorrectionEnable = true
q6ProjectionStrength = 1.0
resamplingEnable = false
closedCapacityResponseEnable = false
closedCapacityVirialKickEnable = false
keepMeanFlowEnable = false
rotationAngle = 0.0
randomRotationSign = false
gridShiftEnable = false
rngSeed = 4935001
thermostatEnable = false
kBT = 0.005
summaryEvery = 1
dumpStateEvery = $STEPS
summaryRoleFilter = fluid
dumpRoleFilter = fluid
initialInactiveSlots = 0
numThreads = 4
speciesRegistryEnable = true
speciesCount = 2
species0 = 1 liquid_incompressible liquid 1.0 0.0 $GAMMA
species1 = 2 gas_compressible gas 0.0 0.0 $GAMMA
speciesRequireRegisteredTypes = true
speciesDiagnosticsEnable = true
speciesDiagnosticsFilename = species_runtime_0493w5.csv
speciesCellDiagnosticsEnable = true
speciesCellDiagnosticsFilename = species_cell_0493w5.csv
speciesQ6Enable = true
speciesQ6Mode = independent_masked
speciesQ6Sensitivity = 1.0
speciesQ6AlphaEpsilon = 1.0e-14
speciesQ6FallbackMode = fatal
speciesQ6ComparisonTolerance = 1.0e-11
speciesQ6MinOccupancyFraction = $MIN_OCC
PARAMS
}

run_profile() {
  local profile=$1
  local case_root="$RUN_ROOT/$profile"
  local state="$RUN_ROOT/states/${profile}.smpcd"
  local params="$case_root/params/params.kv"
  local out="$case_root/output"
  python3 scripts/generate_0493w5_independent_masked_state.py \
    --output "$state" --profile "$profile" --nx "$NX" --ny "$NY" --gamma "$GAMMA"
  write_params "$profile" "$state" "$out" "$params"
  Q6_STRICT=1
  suite_export_cuda_flags_0434 src-q6 periodic
  export SRC_LIVE_VIS_ENABLE=0 MPCD_LIVE_VIS_ENABLE=0
  export MPCD_FILTERED_FIELD_RECORDING_0432=0
  echo "[0493w5] profile=$profile grid=${NX}x${NY} gamma=$GAMMA minOcc=$MIN_OCC"
  "$BIN" "$params" >"$RUN_ROOT/logs/${profile}.log" 2>&1
}

run_profile full
run_profile islands
run_profile mixed60
run_profile mixed40

python3 - "$RUN_ROOT" "$NX" "$NY" "$GAMMA" "$STEPS" <<'PY'
import csv, json, math, struct, sys
from pathlib import Path

root = Path(sys.argv[1])
nx, ny, gamma, steps = map(int, sys.argv[2:])


def last_rows(path):
    rows = list(csv.DictReader(path.open()))
    by_type = {}
    for r in rows:
        by_type[int(r["type"])] = r
    return by_type


def read_state(path):
    data = path.read_bytes()
    off = 16
    version, endian, dim, layout, n, has_type, has_mass, role_bytes, type_bytes = struct.unpack_from("<IIIIQIIII", data, off)
    off += struct.calcsize("<IIIIQIIII") + 8 * 8
    def take(fmt, size):
        nonlocal off
        vals = struct.unpack_from(f"<{n}{fmt}", data, off)
        off += n * size
        return vals
    x = take("d", 8); y = take("d", 8); vx = take("d", 8); vy = take("d", 8)
    typ = take("I", 4); mass = take("d", 8); role = take("B", 1)
    return vx, vy, typ, role

for profile in ("full", "islands", "mixed60", "mixed40"):
    case = root / profile
    audit = last_rows(case / "output" / "cuda_species_q6_independent_masked_0493w5.csv")
    liquid = audit[1]
    gas = audit[2]
    meta = json.loads((root / "states" / f"{profile}.smpcd.json").read_text())
    liquid_fraction = 0.40 if profile == "mixed40" else 1.0
    expected_cells = 0 if liquid_fraction < float(liquid["minOccupancyFraction"]) else int(meta["cells_by_type"]["1"])
    expected_particles = 0 if expected_cells == 0 else int(meta["particles_by_type"]["1"])
    if int(liquid["activeCells"]) != expected_cells:
        raise SystemExit(f"{profile}: activeCells {liquid['activeCells']} != {expected_cells}")
    if int(liquid["correctedParticles"]) != expected_particles:
        raise SystemExit(f"{profile}: correctedParticles {liquid['correctedParticles']} != {expected_particles}")
    if int(liquid["converged"]) != 1:
        raise SystemExit(f"{profile}: liquid solve did not converge")
    if expected_cells:
        before = float(liquid["divBeforeRms"])
        after = float(liquid["divAfterRms"])
        if not (before > 0.0 and after <= max(1.0e-8, 1.0e-5 * before)):
            raise SystemExit(f"{profile}: insufficient divergence reduction before={before} after={after}")
    if int(gas["activeCells"]) != 0 or int(gas["correctedParticles"]) != 0:
        raise SystemExit(f"{profile}: disabled gas received Q6 support/correction")

initial = root / "states" / "islands.smpcd"
final = root / "islands" / "output" / f"state_step_{steps:08d}.smpcd"
vx0, vy0, typ0, role0 = read_state(initial)
vx1, vy1, typ1, role1 = read_state(final)
if typ0 != typ1 or role0 != role1:
    raise SystemExit("islands: particle type/role arrays changed")
gas_changed = 0.0
liquid_changed = 0.0
for a, b, c, d, t, role in zip(vx0, vy0, vx1, vy1, typ0, role0):
    if role != 1:
        continue
    dv = max(abs(c-a), abs(d-b))
    if t == 2:
        gas_changed = max(gas_changed, dv)
    elif t == 1:
        liquid_changed = max(liquid_changed, dv)
if gas_changed > 1.0e-13:
    raise SystemExit(f"islands: disabled gas velocity changed beyond no-op roundoff: {gas_changed}")
if not liquid_changed > 0.0:
    raise SystemExit("islands: projected liquid velocity did not change")
print(f"[0493w5] PASS full+islands+mixed60+mixed40 gasMaxDelta={gas_changed:.3e} liquidMaxDelta={liquid_changed:.3e}")
PY
