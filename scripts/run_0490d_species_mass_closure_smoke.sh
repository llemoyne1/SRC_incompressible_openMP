#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_0490d}"
RUN_ROOT="${RUN_ROOT:-runs/0490d_species_mass_closure_smoke}"
SEED="${SEED:-1628493}"

[[ -x "$BIN" ]] || { echo "[0490d] ERROR missing binary: $BIN" >&2; exit 127; }
rm -rf "$RUN_ROOT"
mkdir -p "$RUN_ROOT/init" "$RUN_ROOT/output" "$RUN_ROOT/logs"

STATE="$RUN_ROOT/init/state.smpcd"
PARAMS="$RUN_ROOT/params_0490d.kv"
LOG="$RUN_ROOT/logs/run.log"

python3 scripts/src_mpcd_case_generator_0434.py \
  --case uniform --state "$STATE" \
  --Lx 6.0 --Ly 1.0 --Nx 6 --Ny 1 --gamma 4 \
  --kBT 0.0 --mass 1.0 --seed "$SEED" --u0 0.0 \
  --velocity-mode zero --background-type 1 --inactive-slots 24

python3 - "$STATE" <<'PY_STATE_0490D'
import struct, sys
p=sys.argv[1]
b=bytearray(open(p,'rb').read())
version,endian,dim,flags,n,has_mass,has_role,mass_bytes,type_bytes=struct.unpack_from('<IIIIQIIII',b,16)
if version != 2 or dim != 2 or has_mass != 1 or has_role != 1 or type_bytes != 4:
    raise SystemExit('[0490d] FAIL unsupported state layout')
off=16+struct.calcsize('<IIIIQIIII')+struct.calcsize('<8Q')
type_off=off+4*8*n
mass_off=type_off+4*n
role_off=mass_off+8*n
# Six cells, four real particles each:
# 0 liquid mass 2, 1 liquid mass 6,
# 2 mixed mass 2, 3 mixed mass 6,
# 4 gas mass 2, 5 gas mass 6.
for i in range(n):
    role=struct.unpack_from('<B',b,role_off+i)[0]
    if role != 1:
        continue
    cell=i//4
    local=i%4
    if cell in (0,2,4):
        mass=0.5
    else:
        mass=1.5
    if cell in (0,1):
        typ=1
    elif cell in (2,3):
        typ=1 if local < 2 else 2
    else:
        typ=2
    struct.pack_into('<I',b,type_off+4*i,typ)
    struct.pack_into('<d',b,mass_off+8*i,mass)
open(p,'wb').write(b)
PY_STATE_0490D

cat > "$PARAMS" <<PARAMS_0490D
inputState = $STATE
outputDir = $RUN_ROOT/output
Lx = 6.0
Ly = 1.0
Nx = 6
Ny = 1
dt = 0.005
nSteps = 1
bcLeft = periodic
bcRight = periodic
bcBottom = periodic
bcTop = periodic
srcClassicCudaModeEnable = false
projectionEnable = false
resamplingEnable = true
resamplingExtractionEnable = false
resamplingInsertionEnable = false
resamplingRemapEnable = true
resamplingThermalRenormalizationEnable = false
resamplingMassRenormalizationPeriod = 1
resamplingMassGuardEnable = false
resamplingLatentActivationEnable = false
resamplingTargetCellMass = 4.0
resamplingPopulationNMin = 1
resamplingPopulationNTarget = 4
resamplingPopulationNMax = 8
thermostatEnable = false
rotationAngle = 0.0
randomRotationSign = false
gridShiftEnable = false
rngSeed = $SEED
summaryEvery = 1
dumpStateEvery = 0
summaryRoleFilter = fluid
dumpRoleFilter = fluid
numThreads = 4
speciesRegistryEnable = true
speciesCount = 2
species0 = 1 liquid_phase liquid 1.0 1.0 4.0
species1 = 2 gas_phase gas 0.0 0.0 4.0
speciesRequireRegisteredTypes = true
speciesDiagnosticsEnable = true
speciesDiagnosticsFilename = species_runtime_0490d.csv
speciesCellDiagnosticsEnable = true
speciesCellDiagnosticsFilename = species_cell_runtime_0490d.csv
speciesResamplingMassClosureEnable = true
PARAMS_0490D

MPCD_CUDA_RESAMPLING_PIPELINE_APPLY_0448=0 \
MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297=0 \
MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=0 \
MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251=0 \
MPCD_CUDA_CLASSIC_SRC_PERIODIC_RESIDENT_0260=0 \
MPCD_CUDA_STREAMING_PERIODIC_0245=0 \
  "$BIN" "$PARAMS" | tee "$LOG"

CELL_CSV="$RUN_ROOT/output/species_cell_runtime_0490d.csv"
SPECIES_CSV="$RUN_ROOT/output/species_runtime_0490d.csv"
[[ -s "$CELL_CSV" ]] || { echo "[0490d] FAIL missing $CELL_CSV" >&2; exit 3; }
[[ -s "$SPECIES_CSV" ]] || { echo "[0490d] FAIL missing $SPECIES_CSV" >&2; exit 3; }

python3 - "$CELL_CSV" "$SPECIES_CSV" <<'PY_CHECK_0490D'
import csv, math, sys
from collections import defaultdict
cell_rows=list(csv.DictReader(open(sys.argv[1],newline='')))
species_rows=list(csv.DictReader(open(sys.argv[2],newline='')))
by_step_cell=defaultdict(dict)
for r in cell_rows:
    by_step_cell[(int(r['step']),int(r['cell']))][int(r['type'])]=r
expected_total=[4.0,4.0,3.0,5.0,2.0,6.0]
expected_type1=[4.0,4.0,1.5,2.5,0.0,0.0]
expected_type2=[0.0,0.0,1.5,2.5,2.0,6.0]
for c in range(6):
    rr=by_step_cell[(1,c)]
    m1=float(rr[1]['mass'])
    m2=float(rr[2]['mass'])
    if not math.isclose(m1,expected_type1[c],rel_tol=0.0,abs_tol=1e-11):
        raise SystemExit(f'[0490d] FAIL cell={c} liquid={m1}')
    if not math.isclose(m2,expected_type2[c],rel_tol=0.0,abs_tol=1e-11):
        raise SystemExit(f'[0490d] FAIL cell={c} gas={m2}')
    if not math.isclose(m1+m2,expected_total[c],rel_tol=0.0,abs_tol=1e-11):
        raise SystemExit(f'[0490d] FAIL cell={c} total={m1+m2}')
    if c in (2,3):
        lf=float(rr[1]['liquidFractionProxy'])
        gf=float(rr[1]['gasFractionProxy'])
        if not math.isclose(lf,0.5,abs_tol=1e-12) or not math.isclose(gf,0.5,abs_tol=1e-12):
            raise SystemExit(f'[0490d] FAIL mixed composition cell={c} lf={lf} gf={gf}')
by_step=defaultdict(dict)
for r in species_rows:
    by_step[int(r['step'])][int(r['type'])]=r
for t in (1,2):
    m0=float(by_step[0][t]['totalMass'])
    m1=float(by_step[1][t]['totalMass'])
    if not math.isclose(m0,12.0,abs_tol=1e-11) or not math.isclose(m1,12.0,abs_tol=1e-11):
        raise SystemExit(f'[0490d] FAIL global type={t} mass0={m0} mass1={m1}')
print('[0490d] PASS')
print('[0490d] final_cell_masses=' + ','.join(f'{x:.17g}' for x in expected_total))
print('[0490d] liquid_mass_initial=12 liquid_mass_final=12')
print('[0490d] gas_mass_initial=12 gas_mass_final=12')
print('[0490d] mixed_fractions_preserved=1')
PY_CHECK_0490D

echo "[0490d] CELL_CSV=$CELL_CSV"
echo "[0490d] SPECIES_CSV=$SPECIES_CSV"
echo "[0490d] LOG=$LOG"
