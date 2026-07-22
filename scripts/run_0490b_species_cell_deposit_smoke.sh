#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_0490b}"
RUN_ROOT="${RUN_ROOT:-runs/0490b_species_cell_deposit_smoke}"
NX="${NX:-12}"
NY="${NY:-4}"
GAMMA="${GAMMA:-6}"
SEED="${SEED:-1628491}"

rm -rf "$RUN_ROOT"
mkdir -p "$RUN_ROOT/init" "$RUN_ROOT/output" "$RUN_ROOT/logs"

STATE="$RUN_ROOT/init/two_species_static.smpcd"
PARAMS="$RUN_ROOT/params_0490b.kv"
LOG="$RUN_ROOT/logs/run.log"

python3 scripts/src_mpcd_case_generator_0434.py \
  --case uniform --state "$STATE" \
  --Lx 3.0 --Ly 1.0 --Nx "$NX" --Ny "$NY" --gamma "$GAMMA" \
  --kBT 0.0 --mass 1.0 --seed "$SEED" --u0 0.0 \
  --velocity-mode zero --background-type 2 --inactive-slots 0

python3 - "$STATE" "$NX" "$NY" "$GAMMA" <<'PY'
import math
import struct
import sys

path = sys.argv[1]
nx, ny, gamma = map(int, sys.argv[2:])
data = bytearray(open(path, 'rb').read())
version, endian, dim, flags, n, has_mass, has_role, mass_bytes, type_bytes = struct.unpack_from(
    '<IIIIQIIII', data, 16)
if version != 2 or dim != 2 or has_mass != 1 or has_role != 1 or type_bytes != 4:
    raise SystemExit('[0490b] FAIL unsupported state layout')
off = 16 + struct.calcsize('<IIIIQIIII') + struct.calcsize('<8Q')
x_off = off
type_off = off + 4 * 8 * n
mass_off = type_off + 4 * n
role_off = mass_off + 8 * n
per_cell = {}
for k in range(n):
    if struct.unpack_from('<B', data, role_off + k)[0] != 1:
        continue
    x = struct.unpack_from('<d', data, x_off + 8*k)[0]
    ix = min(nx - 1, max(0, int(math.floor(x / (3.0 / nx)))))
    cell = k // gamma
    local = per_cell.get(cell, 0)
    per_cell[cell] = local + 1
    if ix < nx // 3:
        typ, mass = 1, 2.0
    elif ix < 2 * nx // 3:
        typ, mass = (1, 2.0) if local % 2 == 0 else (2, 1.0)
    else:
        typ, mass = 2, 1.0
    struct.pack_into('<I', data, type_off + 4*k, typ)
    struct.pack_into('<d', data, mass_off + 8*k, mass)
open(path, 'wb').write(data)
PY

cat > "$PARAMS" <<PARAMS
inputState = $STATE
outputDir = $RUN_ROOT/output
Lx = 3.0
Ly = 1.0
Nx = $NX
Ny = $NY
dt = 0.005
nSteps = 1
bcLeft = periodic
bcRight = periodic
bcBottom = periodic
bcTop = periodic
srcClassicCudaModeEnable = false
projectionEnable = false
resamplingEnable = false
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
species0 = 1 liquid_phase liquid 1.0 1.0 12.0
species1 = 2 gas_phase gas 0.0 0.0 6.0
speciesRequireRegisteredTypes = true
speciesDiagnosticsEnable = true
speciesDiagnosticsFilename = species_runtime_0490b.csv
speciesCellDiagnosticsEnable = true
speciesCellDiagnosticsFilename = species_cell_runtime_0490b.csv
PARAMS

[[ -x "$BIN" ]] || { echo "[0490b] ERROR missing binary: $BIN" >&2; exit 127; }
"$BIN" "$PARAMS" | tee "$LOG"

CELL_CSV="$RUN_ROOT/output/species_cell_runtime_0490b.csv"
SPECIES_CSV="$RUN_ROOT/output/species_runtime_0490b.csv"
[[ -s "$CELL_CSV" ]] || { echo "[0490b] FAIL missing $CELL_CSV" >&2; exit 3; }
[[ -s "$SPECIES_CSV" ]] || { echo "[0490b] FAIL missing $SPECIES_CSV" >&2; exit 3; }

python3 - "$CELL_CSV" "$SPECIES_CSV" "$NX" "$NY" "$GAMMA" <<'PY'
import csv
import math
import sys
from collections import defaultdict

cell_path, species_path = sys.argv[1], sys.argv[2]
nx, ny, gamma = map(int, sys.argv[3:])
rows = list(csv.DictReader(open(cell_path, newline='')))
final = [r for r in rows if int(r['step']) == 1]
if len(final) != nx * ny * 2:
    raise SystemExit(f"[0490b] FAIL final_rows={len(final)}")
by_cell = defaultdict(dict)
for r in final:
    by_cell[int(r['cell'])][int(r['type'])] = r
pure_liquid = mixed = pure_gas = 0
for cell, rr in by_cell.items():
    ix = int(rr[1]['ix'])
    if int(rr[1]['count']) + int(rr[2]['count']) != gamma:
        raise SystemExit(f"[0490b] FAIL count cell={cell}")
    lf = float(rr[1]['liquidFractionProxy'])
    gf = float(rr[1]['gasFractionProxy'])
    if not math.isclose(lf + gf, 1.0, abs_tol=1e-12):
        raise SystemExit(f"[0490b] FAIL fractions cell={cell}")
    if ix < nx // 3:
        pure_liquid += 1
        exp = (gamma, 0, gamma*2.0, 0.0, 1, 1.0, 0.0, 1)
    elif ix < 2 * nx // 3:
        mixed += 1
        exp = (gamma//2, gamma//2, gamma, gamma/2, 2, 0.5, 0.5, 1)
    else:
        pure_gas += 1
        exp = (0, gamma, 0.0, gamma*1.0, 1, 0.0, 1.0, 2)
    n1, n2, m1, m2, active, elf, egf, dom = exp
    if (int(rr[1]['count']), int(rr[2]['count'])) != (n1, n2):
        raise SystemExit(f"[0490b] FAIL species counts cell={cell}")
    if not math.isclose(float(rr[1]['mass']), m1, abs_tol=1e-12):
        raise SystemExit(f"[0490b] FAIL liquid mass cell={cell}")
    if not math.isclose(float(rr[2]['mass']), m2, abs_tol=1e-12):
        raise SystemExit(f"[0490b] FAIL gas mass cell={cell}")
    if int(rr[1]['activeSpeciesCount']) != active or int(rr[1]['dominantType']) != dom:
        raise SystemExit(f"[0490b] FAIL class cell={cell}")
    if not math.isclose(lf, elf, abs_tol=1e-12) or not math.isclose(gf, egf, abs_tol=1e-12):
        raise SystemExit(f"[0490b] FAIL phase fraction cell={cell}")

srows = list(csv.DictReader(open(species_path, newline='')))
sfinal = {int(r['type']): r for r in srows if int(r['step']) == 1}
expected_m1 = ny * ((nx//3)*gamma*2.0 + (nx//3)*(gamma//2)*2.0)
expected_m2 = ny * ((nx//3)*(gamma//2) + (nx//3)*gamma)
if not math.isclose(float(sfinal[1]['totalMass']), expected_m1, abs_tol=1e-12):
    raise SystemExit('[0490b] FAIL liquid global mass')
if not math.isclose(float(sfinal[2]['totalMass']), expected_m2, abs_tol=1e-12):
    raise SystemExit('[0490b] FAIL gas global mass')
print('[0490b] PASS')
print(f'[0490b] final_rows={len(final)} cells={len(by_cell)}')
print(f'[0490b] pure_liquid_cells={pure_liquid} mixed_cells={mixed} pure_gas_cells={pure_gas}')
print(f'[0490b] liquid_mass={expected_m1:.17g} gas_mass={expected_m2:.17g}')
PY

echo "[0490b] CELL_CSV=$CELL_CSV"
echo "[0490b] SPECIES_CSV=$SPECIES_CSV"
echo "[0490b] LOG=$LOG"
