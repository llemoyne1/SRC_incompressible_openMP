#!/usr/bin/env bash
set -euo pipefail

# 0493x14f-fix1 — exact quick qualification of the per-type thermostat on the
# actual liquid/gas src-q6-g-f production path.
#
# Difference versus the first x14f probe:
#   - gridShift=false intentionally, so the final dump can reconstruct exactly
#     the collision/thermostat cells;
#   - qualification uses cell-local per-type thermal energy, not the global
#     apparent temperature polluted by resolved hydrodynamic velocity variance.
#
# This wrapper never creates or modifies ./livevis_control.kv.

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

CASE_LABEL="${CASE_LABEL:-0493x14f_species_thermostat_q6gf_exact}"
BASE_RUN_ROOT="${BASE_RUN_ROOT:-runs/$CASE_LABEL}"

NX="${NX:-128}"
NY="${NY:-64}"
Lx="${Lx:-2.0}"
Ly="${Ly:-1.0}"
GAMMA="${GAMMA:-8}"
STEPS="${STEPS:-200}"
DT="${DT:-0.002}"

KBT_GAS="${KBT_GAS:-0.08}"
KBT_LIQUID="${KBT_LIQUID:-0.02}"
LIQUID_PARTICLE_MASS="${LIQUID_PARTICLE_MASS:-1.0}"
GAS_PARTICLE_MASS="${GAS_PARTICLE_MASS:-0.1}"

UIN="${UIN:-0.10}"
INLET_HEIGHT_CELLS="${INLET_HEIGHT_CELLS:-16}"
SUMMARY_EVERY="${SUMMARY_EVERY:-20}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-$STEPS}"
THERMOSTAT_MIN_PARTICLES="${THERMOSTAT_MIN_PARTICLES:-3}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"

export CASE_LABEL BASE_RUN_ROOT NX NY Lx Ly GAMMA STEPS DT
# x6g gas EOS still uses global KBT in the current code. Keep it equal to the
# gas thermostat target so this test isolates thermostat routing.
export KBT="$KBT_GAS"
export THERMOSTAT_TARGET_KBT="$KBT_GAS"

export LIQUID_PARTICLE_MASS GAS_PARTICLE_MASS
export UIN INLET_HEIGHT_CELLS SUMMARY_EVERY DUMP_STATE_EVERY
export THERMOSTAT_MIN_PARTICLES

export SPECIES_THERMOSTAT_ENABLE=true
export INJECT_THERMOSTAT_TARGET_KBT="$KBT_LIQUID"
export BACKGROUND_THERMOSTAT_TARGET_KBT="$KBT_GAS"

export RUN_MODES=src-q6-g-f
export RUN_OK_LIQUID_SURFACE_ENABLE=1
export SURFACE_TENSION_SIGMA=0.0
export PHASE_INTERFACE_KINETIC_REFLECTION_FRACTION=0.0
export SPECIES_RESAMPLING_ENABLE=false

# Intentional for this exact audit.
export GRID_SHIFT_ENABLE=false

export LIVE_VIS_ENABLE=0
export LIVE_VIS_HOLD_ON_EXIT=0
export FILTERED_RECORDING_ENABLE=0
export RECORD_ENABLE=false
export LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
export PREFLIGHT_ONLY

printf '===== 0493x14f-fix1 src-q6-g-f exact per-type thermostat =====\n'
printf 'PATHS: runner=%s backend=%s outputRoot=%s\n' \
  "$ROOT/scripts/run_ok_0493x14f_species_thermostat_q6gf_exact.sh" \
  "$ROOT/scripts/run_ok_injection_type1_into_type2.sh" "$BASE_RUN_ROOT"
printf 'GRID: L=%sx%s N=%sx%s gamma=%s dt=%s steps=%s gridShift=false\n' \
  "$Lx" "$Ly" "$NX" "$NY" "$GAMMA" "$DT" "$STEPS"
printf 'PATH: src-q6-g-f free_surface_masked + x6g ; sigma=0 ; x10/x12=OFF\n'
printf 'THERMO: liquid(type1,m=%s,kBT=%s) gas(type2,m=%s,kBT=%s) minParticles=%s\n' \
  "$LIQUID_PARTICLE_MASS" "$KBT_LIQUID" "$GAS_PARTICLE_MASS" "$KBT_GAS" "$THERMOSTAT_MIN_PARTICLES"
printf 'AUDIT: exact final cell-local per-type kBT; global apparent kBT is informational only\n'
printf 'NOTE: ./livevis_control.kv is read-only and is not modified\n'

bash "$ROOT/scripts/run_ok_injection_type1_into_type2.sh"
[[ "$PREFLIGHT_ONLY" == 1 ]] && exit 0

RUN_DIR="$BASE_RUN_ROOT/src-q6-g-f"
STATE="$RUN_DIR/init/injection_type1_into_type2_${NX}x${NY}_g${GAMMA}.smpcd"
FINAL="$RUN_DIR/output/state_step_$(printf '%08d' "$STEPS").smpcd"
CSV="$RUN_DIR/output/species_runtime_injection_0493w4.csv"
PARAMS="$RUN_DIR/params/injection_type1_into_type2.kv"

[[ -s "$FINAL" ]] || { echo "[0493x14f-fix1] FAIL missing final dump $FINAL" >&2; exit 3; }
[[ -s "$CSV" ]] || { echo "[0493x14f-fix1] FAIL missing species diagnostics $CSV" >&2; exit 3; }
grep -Eq '^speciesThermostatEnable[[:space:]]*=[[:space:]]*true' "$PARAMS" || {
  echo "[0493x14f-fix1] FAIL species thermostat missing from params" >&2; exit 3; }
grep -Eq '^speciesQ6Mode[[:space:]]*=[[:space:]]*free_surface_masked' "$PARAMS" || {
  echo "[0493x14f-fix1] FAIL q6-g-f free_surface_masked missing" >&2; exit 3; }
grep -Eq '^gridShiftEnable[[:space:]]*=[[:space:]]*false' "$PARAMS" || {
  echo "[0493x14f-fix1] FAIL gridShiftEnable=false missing" >&2; exit 3; }

python3 - "$FINAL" "$CSV" "$NX" "$NY" "$Lx" "$Ly" \
  "$KBT_LIQUID" "$KBT_GAS" "$THERMOSTAT_MIN_PARTICLES" <<'PY'
import csv
import math
import struct
import sys
from collections import defaultdict

state_path, csv_path = sys.argv[1], sys.argv[2]
nx, ny = int(sys.argv[3]), int(sys.argv[4])
lx, ly = float(sys.argv[5]), float(sys.argv[6])
targets = {1: float(sys.argv[7]), 2: float(sys.argv[8])}
minp = int(sys.argv[9])

MAGIC = b"SRCMPCD_STATE"

def read_state(path):
    with open(path, "rb") as f:
        magic = f.read(16)
        if not magic.startswith(MAGIC):
            raise SystemExit(f"[0493x14f-fix1] FAIL bad state magic: {magic!r}")
        hfmt = "<IIIIQIIII"
        raw = f.read(struct.calcsize(hfmt))
        version, endian, dim, layout, n, has_type, has_mass, real_size, type_size = struct.unpack(hfmt, raw)
        reserved = struct.unpack("<8Q", f.read(64))
        if endian != 0x01020304 or dim != 2 or layout != 1:
            raise SystemExit("[0493x14f-fix1] FAIL unsupported SMPD header")
        if not has_type or not has_mass or real_size != 8 or type_size != 4:
            raise SystemExit("[0493x14f-fix1] FAIL unsupported particle layout")
        n = int(n)
        def vec(fmt, size):
            b = f.read(size*n)
            if len(b) != size*n:
                raise SystemExit("[0493x14f-fix1] FAIL truncated state")
            return struct.unpack(f"<{n}{fmt}", b)
        x=vec("d",8); y=vec("d",8); vx=vec("d",8); vy=vec("d",8)
        typ=vec("I",4); mass=vec("d",8)
        if version >= 2:
            role_size = int(reserved[1]) if reserved[1] else 1
            if role_size != 1:
                raise SystemExit("[0493x14f-fix1] FAIL unsupported role size")
            role=vec("B",1)
        else:
            role=(1,)*n
    return dict(n=n,x=x,y=y,vx=vx,vy=vy,typ=typ,mass=mass,role=role)

st = read_state(state_path)

cells = defaultdict(list)
type_ids = defaultdict(list)
for i in range(st["n"]):
    if st["role"][i] != 1:
        continue
    t = int(st["typ"][i])
    if t not in targets:
        continue
    # Closed numerical box coordinates. Clamp particles exactly on the upper
    # edge into the last cell, matching the fixed physical grid convention.
    xx = min(max(st["x"][i], 0.0), math.nextafter(lx, 0.0))
    yy = min(max(st["y"][i], 0.0), math.nextafter(ly, 0.0))
    ix = min(nx-1, max(0, int(math.floor(xx/lx*nx))))
    iy = min(ny-1, max(0, int(math.floor(yy/ly*ny))))
    cells[(iy*nx+ix,t)].append(i)
    type_ids[t].append(i)

tol = 2.0e-9
for t in (1,2):
    ids_all = type_ids[t]
    if not ids_all:
        raise SystemExit(f"[0493x14f-fix1] FAIL no fluid particles for type {t}")

    # Informational global apparent temperature. This includes resolved
    # cell-to-cell mean-flow variance and is NOT the thermostat target.
    M = sum(st["mass"][i] for i in ids_all)
    Px = sum(st["mass"][i]*st["vx"][i] for i in ids_all)
    Py = sum(st["mass"][i]*st["vy"][i] for i in ids_all)
    ux, uy = Px/M, Py/M
    Kglob = sum(0.5*st["mass"][i]*((st["vx"][i]-ux)**2+(st["vy"][i]-uy)**2)
                for i in ids_all)
    app = Kglob/max(1,len(ids_all)-1)

    sumK = 0.0
    sumHalfDof = 0
    eligible_particles = 0
    eligible_cells = 0
    max_rel = 0.0
    for (c,tt), ids in cells.items():
        if tt != t or len(ids) < minp:
            continue
        Mc = sum(st["mass"][i] for i in ids)
        Pxc = sum(st["mass"][i]*st["vx"][i] for i in ids)
        Pyc = sum(st["mass"][i]*st["vy"][i] for i in ids)
        ucx, ucy = Pxc/Mc, Pyc/Mc
        Kc = sum(0.5*st["mass"][i]*((st["vx"][i]-ucx)**2+(st["vy"][i]-ucy)**2)
                 for i in ids)
        if not (Kc > 1.0e-30):
            continue
        kbt = Kc/(len(ids)-1)  # 2-D: K=(n-1) kBT
        rel = abs(kbt/targets[t]-1.0)
        max_rel = max(max_rel, rel)
        sumK += Kc
        sumHalfDof += len(ids)-1
        eligible_particles += len(ids)
        eligible_cells += 1

    if sumHalfDof <= 0:
        raise SystemExit(f"[0493x14f-fix1] FAIL type {t}: no eligible thermostat cells")
    weighted = sumK/sumHalfDof
    coverage = eligible_particles/len(ids_all)

    print(f"[0493x14f-fix1] type={t} N={len(ids_all)} globalApparentKBT={app:.12g} "
          f"exactCellKBT={weighted:.12g} target={targets[t]:.12g} "
          f"maxRel={max_rel:.3e} coverage={coverage:.6f} eligibleCells={eligible_cells}")

    if not math.isfinite(weighted) or max_rel > tol:
        raise SystemExit(
            f"[0493x14f-fix1] FAIL type {t}: exact cell target maxRel={max_rel:.3e} > {tol:.3e}")
    # The injected liquid occupies only a compact inlet region, so allow some
    # under-populated edge cells; the gas should be essentially fully covered.
    coverage_floor = 0.80 if t == 1 else 0.95
    if coverage < coverage_floor:
        raise SystemExit(
            f"[0493x14f-fix1] FAIL type {t}: coverage={coverage:.6f} < {coverage_floor:.2f}")

# Also report the last species-runtime row without using it as the exact target.
rows=list(csv.DictReader(open(csv_path,newline="")))
last=max(int(r["step"]) for r in rows)
for t in (1,2):
    rr=[r for r in rows if int(r["step"])==last and int(r["type"])==t]
    if rr:
        r=rr[-1]
        print(f"[0493x14f-fix1] speciesCSV type={t} step={last} "
              f"nFluid={r['nFluid']} meanV=({r['meanVx']},{r['meanVy']})")

print("[0493x14f-fix1] PASS src-q6-g-f exact species thermostat qualification")
PY
