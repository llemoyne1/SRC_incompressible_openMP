#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

./scripts/build_src_mpcd_base.sh

RUN_DIR="runs/resampling_integrated_void_rich_latent_smoke_0125"
rm -rf "$RUN_DIR"
mkdir -p "$RUN_DIR"
STATE="$RUN_DIR/initial_integrated_v2.smpcd"
THREADS="${NUM_THREADS:-2}"

python3 - <<'PY'
import pathlib
import struct

root = pathlib.Path("runs/resampling_integrated_void_rich_latent_smoke_0125")
root.mkdir(parents=True, exist_ok=True)
path = root / "initial_integrated_v2.smpcd"
Nx = 8
Ny = 4
Nlatent = 4
Ninactive = 2

x=[]; y=[]; vx=[]; vy=[]; type_=[]; mass=[]; role=[]

def add_particle(cell, px, py, ux, uy, m, typ=0, r=1):
    ix = cell % Nx
    iy = cell // Nx
    x.append((ix + px) / Nx)
    y.append((iy + py) / Ny)
    vx.append(ux)
    vy.append(uy)
    type_.append(typ)
    mass.append(m)
    role.append(r)

# Cells:
#   0: empty wet void, to be seeded by Latent->Fluid activation.
#   1: poor cell with one very light particle; later filled by donor insertion
#      and repaired by mass guard.
#   2: rich donor cell, source for extraction/insertion.
# Other cells: already at target mass 4.
for c in range(Nx * Ny):
    if c == 0:
        continue
    if c == 1:
        add_particle(c, 0.35, 0.35, 0.40, -0.10, 0.20, typ=1, r=1)
        continue
    if c == 2:
        donor_vel = [(-0.30, 0.20), (0.25, -0.15), (0.10, 0.35), (-0.15, -0.25),
                     (0.05, 0.05), (-0.05, 0.15), (0.20, 0.00), (-0.10, -0.10)]
        for p, (ux, uy) in enumerate(donor_vel):
            add_particle(c, 0.18 + 0.16 * (p % 4), 0.30 + 0.22 * (p // 4), ux, uy, 1.0, typ=p % 2, r=1)
        continue
    for p in range(4):
        add_particle(c, 0.25 + 0.25 * (p % 2), 0.25 + 0.25 * (p // 2),
                     0.02 * (p - 1.5), -0.01 * (p - 1.5), 1.0, typ=p % 2, r=1)

Nfluid = len(role)
assert Nfluid == 125, Nfluid
assert abs(sum(mass) - 124.2) < 1e-12, sum(mass)

# Four latent particles are sufficient to seed exactly the empty wet void cell.
# The remaining poor cell must therefore be repaired by extraction/insertion.
for i in range(Nlatent):
    x.append(1.2 + 0.01 * i)
    y.append(1.1 + 0.01 * i)
    vx.append(9.0)
    vy.append(-9.0)
    type_.append(20 + i)
    mass.append(10.0)
    role.append(2)  # Latent

# Inactive pool slots are not needed by the conservative recycle path, but they
# ensure the integrated test also checks persistent dormant roles.
for i in range(Ninactive):
    x.append(-0.2 - 0.01 * i)
    y.append(-0.2 - 0.01 * i)
    vx.append(-5.0)
    vy.append(5.0)
    type_.append(99)
    mass.append(20.0)
    role.append(0)  # Inactive

Np = len(x)
with path.open("wb") as f:
    f.write(b"SRCMPCD_STATE" + b"\0\0\0")
    f.write(struct.pack("<IIIIQIIII", 2, 0x01020304, 2, 1, Np, 1, 1, Nx, Ny))
    reserved = [0] * 8
    reserved[0] = 1
    reserved[1] = 1
    f.write(struct.pack("<8Q", *reserved))
    for arr in (x, y, vx, vy):
        f.write(struct.pack("<" + "d" * Np, *arr))
    f.write(struct.pack("<" + "I" * Np, *type_))
    f.write(struct.pack("<" + "d" * Np, *mass))
    f.write(struct.pack("<" + "B" * Np, *role))
print(path)
print(f"Nfluid={Nfluid} Nlatent={Nlatent} Ninactive={Ninactive} Np={Np} realMass={sum(m for m,r in zip(mass, role) if r == 1)}")
PY

cat > "$RUN_DIR/params_integrated.kv" <<KV
inputState = $STATE
outputDir = $RUN_DIR/out
Lx = 1.0
Ly = 1.0
Nx = 8
Ny = 4
dt = 0.001
nSteps = 1
alphaDeg = 0
randomRotationSign = false
gridShiftEnable = false
rngSeed = 1250
bcX = periodic
bcY = periodic
method = classic
thermostatEnable = false
kBT = 0.01
resamplingEnable = true
resamplingTargetCellMass = 4.0
resamplingWetMaskMode = active_domain
resamplingWetCellMassThreshold = 0.0
resamplingPoorCellMassFraction = 0.75
resamplingRichCellMassFraction = 1.5
resamplingLatentActivationEnable = true
resamplingLatentActivationMaxPerCell = 4
resamplingLatentActivationParticleMass = 1.0
resamplingExtractionEnable = true
resamplingInsertionEnable = true
resamplingRemapEnable = true
resamplingThermalRenormalizationEnable = true
resamplingMassGuardEnable = true
resamplingParticleMassMin = 0.5
resamplingParticleMassMax = 2.0
summaryEvery = 1
dumpStateEvery = 1
numThreads = $THREADS
KV

./build/src_mpcd_base "$RUN_DIR/params_integrated.kv"

python3 - <<'PY'
import csv
import pathlib
import struct

base = pathlib.Path("runs/resampling_integrated_void_rich_latent_smoke_0125")
summary = base / "out" / "summary_runtime.csv"
with summary.open(newline="") as f:
    rows = list(csv.DictReader(f))
assert len(rows) == 2, len(rows)
initial, final = rows

def I(row, key):
    return int(float(row[key]))

def F(row, key):
    return float(row[key])

# Initial designed pathology: one empty wet void, one poor cell, one rich donor.
assert I(initial, "resampNFluid") == 125
assert I(initial, "resampNLatent") == 4
assert I(initial, "resampNInactive") == 2
assert abs(F(initial, "resampTotalMass") - 124.2) < 1e-12
assert I(initial, "resampEmptyWetCells") == 1
assert I(initial, "resampPoorCells") >= 2
assert I(initial, "resampRichCells") >= 1

# Latent activation must seed the empty wet cell only. The second poor receiver
# remains for the conservative donor->pool->receiver cycle.
assert I(final, "resampLatentActivationAttempted") == 1
assert I(final, "resampLatentActivationApplied") == 1
assert I(final, "resampLatentActivationParticlesActivated") == 4
assert I(final, "resampLatentActivationCellsActivated") == 1
assert abs(F(final, "resampLatentActivationMass") - 4.0) < 1e-12
assert I(final, "resampLatentActivationAllSourcesWereLatent") == 1
assert I(final, "resampLatentActivationNoDryCellsActivated") == 1

# Extraction/insertion recycles donor particles into the remaining poor cell.
assert I(final, "resampExtractionApplyAttempted") == 1
assert I(final, "resampExtractionApplied") == 1
assert I(final, "resampExtractionApplyOpsApplied") == 4
assert abs(F(final, "resampExtractionApplyMass") - 4.0) < 1e-12
assert I(final, "resampInsertionApplyAttempted") == 1
assert I(final, "resampInsertionApplied") == 1
assert I(final, "resampInsertionApplyOpsApplied") == 4
assert abs(F(final, "resampInsertionApplyMass") - 4.0) < 1e-12
assert I(final, "resampInsertionApplyAllSourcesWereInactive") == 1

# Remap/thermal/mass guard should all be active.  The guard repairs the light
# particle in the receiver cell while keeping the final cell masses at target.
assert I(final, "resampRemapApplyAttempted") == 1
assert I(final, "resampRemapApplied") == 1
assert F(final, "resampRemapMaxCellMassRelResidual") < 1e-12
assert I(final, "resampThermalRenormAttempted") == 1
assert I(final, "resampThermalRenormApplied") == 1
assert F(final, "resampThermalRenormEnergyResidualRms") < 1e-12
assert I(final, "resampMassGuardAttempted") == 1
assert I(final, "resampMassGuardApplied") == 1
assert I(final, "resampMassGuardParticlesBelowMinBefore") >= 1
assert I(final, "resampMassGuardParticlesAdjusted") >= 1
assert I(final, "resampMassGuardParticlesBelowMinAfter") == 0
assert I(final, "resampMassGuardParticlesAboveMaxAfter") == 0
assert F(final, "resampMassGuardMassResidualRms") < 1e-12
assert F(final, "resampMassGuardThermalEnergyResidualRms") < 1e-12
assert F(final, "resampMassGuardMomentumResidualRms") < 1e-12

# Final integrated state: all active-domain cells are filled to the mass target;
# no latent slots remain, original inactive slots persist, and role persistence
# is tested from the final V2 dump below.
assert I(final, "resampNFluid") == 129
assert I(final, "resampNLatent") == 0
assert I(final, "resampNInactive") == 2
assert I(final, "resampPoolFreeSlots") == 2
assert I(final, "resampEmptyWetCells") == 0
assert I(final, "resampPoorCells") == 0
assert I(final, "resampRichCells") == 0
assert abs(F(final, "resampTotalMass") - 128.0) < 1e-10
assert F(final, "resampMRelRms") < 1e-12
assert F(final, "resampParticleMassMin") >= 0.5 - 1e-10
assert F(final, "resampParticleMassMax") <= 2.0 + 1e-10

state_path = base / "out" / "state_step_00000001.smpcd"
with state_path.open("rb") as f:
    magic = f.read(16)
    assert magic == b"SRCMPCD_STATE" + b"\0\0\0"
    version, endian, dim, flags, Np, has_type, has_mass, Nx, Ny = struct.unpack("<IIIIQIIII", f.read(40))
    assert version == 2 and has_type == 1 and has_mass == 1
    f.read(8 * 8)
    f.read(8 * Np * 4)  # x,y,vx,vy
    f.read(4 * Np)      # type
    masses = list(struct.unpack("<" + "d" * Np, f.read(8 * Np)))
    roles = list(struct.unpack("<" + "B" * Np, f.read(Np)))
fluid_masses = [m for m, r in zip(masses, roles) if r == 1]
assert roles.count(1) == 129, roles.count(1)
assert roles.count(2) == 0, roles.count(2)
assert roles.count(0) == 2, roles.count(0)
assert min(fluid_masses) >= 0.5 - 1e-10
assert max(fluid_masses) <= 2.0 + 1e-10

print(
    "integrated resampling:",
    f"latentActivated={final['resampLatentActivationParticlesActivated']}",
    f"extracted={final['resampExtractionApplyOpsApplied']}",
    f"inserted={final['resampInsertionApplyOpsApplied']}",
    f"massGuardAdjusted={final['resampMassGuardParticlesAdjusted']}",
    f"fluid={final['resampNFluid']}",
    f"latent={final['resampNLatent']}",
    f"inactive={final['resampNInactive']}",
    f"MRelRms={final['resampMRelRms']}",
)
PY

printf '\n[0125 resampling integrated smoke] OK: void+rich+latent case validates activation, recycle, remap, thermal renorm and mass guard together.\n'
