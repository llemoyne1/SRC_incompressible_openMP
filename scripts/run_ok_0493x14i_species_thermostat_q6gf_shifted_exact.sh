#!/usr/bin/env bash
set -euo pipefail

# 0493x14i — final quick qualification of the per-type thermostat on the
# production src-q6-g-f liquid/gas path with grid shift active and 0272=1.
# Exact validation reconstructs the final shifted SRC collision cells from the
# already-existing persistent-collision audit CSV. The multi-target species
# thermostat intentionally does NOT emit the legacy single-target 0491f CSV.
# No livevis_control.kv write.

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

CASE_LABEL="${CASE_LABEL:-0493x14i_species_thermostat_q6gf_shifted_exact}"
BASE_RUN_ROOT="${BASE_RUN_ROOT:-runs/$CASE_LABEL}"

# ----- physical / numerical parameters: intentionally visible -----
NX="${NX:-128}"
NY="${NY:-64}"
Lx="${Lx:-2.0}"
Ly="${Ly:-1.0}"
GAMMA="${GAMMA:-8}"
STEPS="${STEPS:-200}"
DT="${DT:-0.002}"
SEED="${SEED:-493149}"
ROTATION_ANGLE="${ROTATION_ANGLE:-2.0943951023931953}"

LIQUID_PARTICLE_MASS="${LIQUID_PARTICLE_MASS:-1.0}"
GAS_PARTICLE_MASS="${GAS_PARTICLE_MASS:-0.1}"
KBT_LIQUID="${KBT_LIQUID:-0.02}"
KBT_GAS="${KBT_GAS:-0.08}"
THERMOSTAT_MIN_PARTICLES="${THERMOSTAT_MIN_PARTICLES:-3}"

UIN="${UIN:-0.10}"
INLET_HEIGHT_CELLS="${INLET_HEIGHT_CELLS:-16}"
SUMMARY_EVERY="${SUMMARY_EVERY:-20}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-$STEPS}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"

export CASE_LABEL BASE_RUN_ROOT NX NY Lx Ly GAMMA STEPS DT SEED ROTATION_ANGLE
export LIQUID_PARTICLE_MASS GAS_PARTICLE_MASS UIN INLET_HEIGHT_CELLS
export SUMMARY_EVERY DUMP_STATE_EVERY THERMOSTAT_MIN_PARTICLES PREFLIGHT_ONLY

# x6g — gas pressure EOS — still consumes the global KBT. Keep it equal to the
# gas constitutive target while the thermostat itself is separated by type.
export KBT="$KBT_GAS"
export THERMOSTAT_TARGET_KBT="$KBT_GAS"
export SPECIES_THERMOSTAT_ENABLE=true
export INJECT_THERMOSTAT_TARGET_KBT="$KBT_LIQUID"
export BACKGROUND_THERMOSTAT_TARGET_KBT="$KBT_GAS"

export RUN_MODES=src-q6-g-f
export RUN_OK_LIQUID_SURFACE_ENABLE=1
export SURFACE_TENSION_SIGMA=0.0
export PHASE_INTERFACE_KINETIC_REFLECTION_FRACTION=0.0
export SPECIES_RESAMPLING_ENABLE=false

# Production conditions to qualify here.
export GRID_SHIFT_ENABLE=true
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WORKSPACE_DOWNLOAD_0272=1
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_DISABLE_SKIP_WORKSPACE_DOWNLOAD_0272=0

# Keep the probe isolated from visualisation/recording overhead. The runner
# never creates or rewrites ./livevis_control.kv.
export LIVE_VIS_ENABLE=0
export LIVE_VIS_HOLD_ON_EXIT=0
export FILTERED_RECORDING_ENABLE=0
export RECORD_ENABLE=false
export LIVE_PROGRESS="${LIVE_PROGRESS:-1}"

printf '===== 0493x14i src-q6-g-f shifted exact per-type thermostat =====\n'
printf 'PATHS: runner=%s backend=%s outputRoot=%s\n' \
  "$ROOT/scripts/run_ok_0493x14i_species_thermostat_q6gf_shifted_exact.sh" \
  "$ROOT/scripts/run_ok_injection_type1_into_type2.sh" "$BASE_RUN_ROOT"
printf 'GRID: L=%sx%s N=%sx%s gamma=%s dt=%s steps=%s gridShift=true seed=%s\n' \
  "$Lx" "$Ly" "$NX" "$NY" "$GAMMA" "$DT" "$STEPS" "$SEED"
printf 'SRC: angle=%s common liquid/gas collision\n' "$ROTATION_ANGLE"
printf 'PATH: src-q6-g-f free_surface_masked + x6g ; sigma=0 ; x10/x12=OFF\n'
printf 'THERMO: liquid(type1,m=%s,kBT=%s) gas(type2,m=%s,kBT=%s) minParticles=%s\n' \
  "$LIQUID_PARTICLE_MASS" "$KBT_LIQUID" "$GAS_PARTICLE_MASS" "$KBT_GAS" "$THERMOSTAT_MIN_PARTICLES"
printf 'RESIDENT: 0272 skip-workspace-download=1 ; exact cell audit uses recorded final grid shift\n'
printf 'NOTE: ./livevis_control.kv is read-only and is not modified\n'

bash "$ROOT/scripts/run_ok_injection_type1_into_type2.sh"
[[ "$PREFLIGHT_ONLY" == 1 ]] && exit 0

RUN_DIR="$BASE_RUN_ROOT/src-q6-g-f"
FINAL="$RUN_DIR/output/state_step_$(printf '%08d' "$STEPS").smpcd"
PARAMS="$RUN_DIR/params/injection_type1_into_type2.kv"
COLLISION_AUDIT="$RUN_DIR/output/cuda_persistent_src_collision_thermostat_0215.csv"

[[ -s "$FINAL" ]] || { echo "[0493x14i] FAIL missing final dump $FINAL" >&2; exit 3; }
[[ -s "$COLLISION_AUDIT" ]] || { echo "[0493x14i] FAIL missing collision audit $COLLISION_AUDIT" >&2; exit 3; }
grep -Eq '^speciesThermostatEnable[[:space:]]*=[[:space:]]*true' "$PARAMS" || { echo '[0493x14i] FAIL species thermostat missing' >&2; exit 3; }
grep -Eq '^speciesQ6Mode[[:space:]]*=[[:space:]]*free_surface_masked' "$PARAMS" || { echo '[0493x14i] FAIL free_surface_masked missing' >&2; exit 3; }
grep -Eq '^gridShiftEnable[[:space:]]*=[[:space:]]*true' "$PARAMS" || { echo '[0493x14i] FAIL gridShiftEnable=true missing' >&2; exit 3; }

python3 - "$FINAL" "$COLLISION_AUDIT" "$STEPS" "$NX" "$NY" "$Lx" "$Ly" \
  "$KBT_LIQUID" "$KBT_GAS" "$THERMOSTAT_MIN_PARTICLES" <<'PY'
import csv, math, struct, sys
from collections import defaultdict

state_path, coll_path = sys.argv[1:3]
step = int(sys.argv[3]); nx=int(sys.argv[4]); ny=int(sys.argv[5])
lx=float(sys.argv[6]); ly=float(sys.argv[7])
targets={1:float(sys.argv[8]),2:float(sys.argv[9])}; minp=int(sys.argv[10])

# The collision audit already records the exact random shift used by SRC.
rows=list(csv.DictReader(open(coll_path,newline='')))
rr=[r for r in rows if int(r['step'])==step]
if not rr:
    raise SystemExit(f'[0493x14i] FAIL no collision audit row for step={step}')
r=rr[-1]; sx=float(r['shiftX']); sy=float(r['shiftY'])
if abs(sx)+abs(sy) <= 1e-16:
    raise SystemExit('[0493x14i] FAIL final grid shift unexpectedly zero')
print(f'[0493x14i] finalCollisionShift=({sx:.17g},{sy:.17g}) rowStep={step}')

# 0493x14a intentionally suppresses the legacy 0491f thermostat CSV in
# multi-target mode: its single targetKBT column would be semantically wrong.
# For x14g the causal production check is instead:
#   (1) 0272=1 is forced by this runner, so no host collision-cell vector is
#       available to the Q6 thermostat;
#   (2) x14g now throws if neither the resident SRC cellId bridge nor a valid
#       host vector exists;
#   (3) the run completed, and below we verify the final per-type temperature
#       in the exact shifted SRC cells. Before x14g this same configuration
#       failed that exact check with stale pre-stream Q6 cellIds.
print('[0493x14i] residentBridge precondition PASS 0272=1; run completed without x14g missing-cellId guard')

MAGIC=b'SRCMPCD_STATE'
def read_state(path):
    with open(path,'rb') as f:
        magic=f.read(16)
        if not magic.startswith(MAGIC): raise SystemExit('[0493x14i] FAIL bad state magic')
        hfmt='<IIIIQIIII'; raw=f.read(struct.calcsize(hfmt))
        version,endian,dim,layout,n,has_type,has_mass,real_size,type_size=struct.unpack(hfmt,raw)
        reserved=struct.unpack('<8Q',f.read(64))
        if endian!=0x01020304 or dim!=2 or layout!=1 or not has_type or not has_mass or real_size!=8 or type_size!=4:
            raise SystemExit('[0493x14i] FAIL unsupported state format')
        n=int(n)
        def vec(fmt,size):
            b=f.read(size*n)
            if len(b)!=size*n: raise SystemExit('[0493x14i] FAIL truncated state')
            return struct.unpack(f'<{n}{fmt}',b)
        x=vec('d',8); y=vec('d',8); vx=vec('d',8); vy=vec('d',8); typ=vec('I',4); mass=vec('d',8)
        role=vec('B',1) if version>=2 else (1,)*n
    return dict(n=n,x=x,y=y,vx=vx,vy=vy,typ=typ,mass=mass,role=role)
st=read_state(state_path)

dx=lx/nx; dy=ly/ny
def bounded_index(z,L,d,N):
    i=int(math.floor(z/d))
    return 0 if i<0 else (N-1 if i>=N else i)

cells=defaultdict(list); type_ids=defaultdict(list)
for i in range(st['n']):
    if st['role'][i] != 1: continue
    t=int(st['typ'][i])
    if t not in targets: continue
    # Injection runner is nonperiodic in both directions for collision-cell
    # indexing. CUDA uses floor((x+shift)/d) followed by clamping.
    ix=bounded_index(st['x'][i]+sx,lx,dx,nx)
    iy=bounded_index(st['y'][i]+sy,ly,dy,ny)
    cells[(iy*nx+ix,t)].append(i); type_ids[t].append(i)

tol=2e-9
for t in (1,2):
    ids_all=type_ids[t]
    if not ids_all: raise SystemExit(f'[0493x14i] FAIL no type {t} particles')
    M=sum(st['mass'][i] for i in ids_all)
    Px=sum(st['mass'][i]*st['vx'][i] for i in ids_all); Py=sum(st['mass'][i]*st['vy'][i] for i in ids_all)
    ux=Px/M; uy=Py/M
    Kglob=sum(0.5*st['mass'][i]*((st['vx'][i]-ux)**2+(st['vy'][i]-uy)**2) for i in ids_all)
    app=Kglob/max(1,len(ids_all)-1)
    sumK=0.0; sumHalfDof=0; eligible=0; ecells=0; maxrel=0.0
    for (c,tt),ids in cells.items():
        if tt!=t or len(ids)<minp: continue
        Mc=sum(st['mass'][i] for i in ids)
        Pxc=sum(st['mass'][i]*st['vx'][i] for i in ids); Pyc=sum(st['mass'][i]*st['vy'][i] for i in ids)
        ucx=Pxc/Mc; ucy=Pyc/Mc
        Kc=sum(0.5*st['mass'][i]*((st['vx'][i]-ucx)**2+(st['vy'][i]-ucy)**2) for i in ids)
        if not (Kc>1e-30): continue
        kbt=Kc/(len(ids)-1)  # 2-D: K=(N-1) kBT
        maxrel=max(maxrel,abs(kbt/targets[t]-1.0))
        sumK+=Kc; sumHalfDof+=len(ids)-1; eligible+=len(ids); ecells+=1
    if sumHalfDof<=0: raise SystemExit(f'[0493x14i] FAIL type {t}: no eligible cells')
    exact=sumK/sumHalfDof; coverage=eligible/len(ids_all)
    print(f'[0493x14i] type={t} N={len(ids_all)} globalApparentKBT={app:.12g} exactShiftedCellKBT={exact:.12g} target={targets[t]:.12g} maxRel={maxrel:.3e} coverage={coverage:.6f} eligibleCells={ecells}')
    if maxrel>tol:
        raise SystemExit(f'[0493x14i] FAIL type {t}: exact shifted cell target maxRel={maxrel:.3e} > {tol:.3e}')
    floor=0.80 if t==1 else 0.95
    if coverage<floor:
        raise SystemExit(f'[0493x14i] FAIL type {t}: coverage={coverage:.6f} < {floor:.2f}')

print('[0493x14i] PASS src-q6-g-f production shifted-grid resident species thermostat (x14g bridge)')
PY
