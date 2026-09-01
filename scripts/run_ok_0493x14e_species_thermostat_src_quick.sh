#!/usr/bin/env bash
set -euo pipefail

# 0493x14e — quick qualification of the per-type thermostat on the actual SRC
# production path: common SRC/MPCD collision, random grid shift, then the
# separate resident CUDA thermostat by registered particle type.
# This runner only READS ./livevis_control.kv through the common infrastructure.

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_ok_common.sh"
suite_root_cd_0434

CASE_LABEL="${CASE_LABEL:-0493x14e_species_thermostat_src_quick}"
RUN_OK_ENTRYPOINT="$ROOT/scripts/run_ok_0493x14e_species_thermostat_src_quick.sh"
BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}"
RUN_ROOT="${RUN_ROOT:-runs/$CASE_LABEL}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"

# ----- physical / numerical parameters, intentionally visible -----
NX="${NX:-32}"; NY="${NY:-16}"; Lx=1.0; Ly=1.0
GAMMA="${GAMMA:-20}"
DT="${DT:-0.002}"; STEPS="${STEPS:-1000}"; SEED="${SEED:-493145}"
THREADS="${THREADS:-8}"
ROTATION_ANGLE="${ROTATION_ANGLE:-2.0943951023931953}"
RANDOM_ROTATION_SIGN=true
GRID_SHIFT_ENABLE=true
MASS_TYPE1="${MASS_TYPE1:-1.0}"; MASS_TYPE2="${MASS_TYPE2:-0.1}"
TARGET_TYPE1="${TARGET_TYPE1:-0.02}"; TARGET_TYPE2="${TARGET_TYPE2:-0.08}"
THERMOSTAT_ENABLE=true; THERMOSTAT_MODE=cell_relative_rescale; THERMOSTAT_EVERY=1
THERMOSTAT_TARGET_KBT="$TARGET_TYPE2"; THERMOSTAT_MIN_PARTICLES="${THERMOSTAT_MIN_PARTICLES:-3}"
SUMMARY_EVERY="${SUMMARY_EVERY:-100}"; DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-1000}"
DUMP_ROLE_FILTER=fluid; SUMMARY_ROLE_FILTER=fluid
PARTICLE_MASS="$MASS_TYPE1"; KBT="$TARGET_TYPE2"; U0=0.0; UIN=0.0
INACTIVE_SLOTS=0
SPECIES_RESAMPLING_ENABLE=false
WEIGHTED_RESAMPLING_ENABLE_OVERRIDE=false
CUDA_EMPTY_REFILL_ENABLE_OVERRIDE=false
RESAMPLING_THERMAL_RENORMALIZATION_ENABLE=false
RESAMPLING_MASS_GUARD_ENABLE=false
CUDA_RESAMPLING_CHI_FILTER_ENABLE=false
CUDA_RESAMPLING_CHI_MIN=0.05
GUARD_NMIN=$((GAMMA-4)); GUARD_NTARGET="$GAMMA"; GUARD_NMAX=$((GAMMA+4))
LIVE_VIS_ENABLE=0; FILTERED_RECORDING_ENABLE=0; RECORD_ENABLE=false; PARTICLE_TYPE_FILTER=-1
export LIVE_PROGRESS="${LIVE_PROGRESS:-1}" OMP_NUM_THREADS="$THREADS"

(( GAMMA >= 12 && GAMMA % 2 == 0 )) || { echo "[0493x14e] ERROR GAMMA must be even and >=12" >&2; exit 2; }

suite_defaults_common_0434
suite_compute_derived_0434
if [[ "$CLEAN_RUN_ROOT" == 1 && "$PREFLIGHT_ONLY" != 1 ]]; then rm -rf "$RUN_ROOT"; fi
mkdir -p "$RUN_ROOT/init" "$RUN_ROOT/params" "$RUN_ROOT/output" "$RUN_ROOT/logs"
STATE="$RUN_ROOT/init/two_type_uniform_0493x14e.smpcd"
PARAMS="$RUN_ROOT/params/params_0493x14e.kv"
FINAL="$RUN_ROOT/output/state_step_$(printf '%08d' "$STEPS").smpcd"
LOG="$RUN_ROOT/logs/run_0493x14e.log"; TIMEFILE="$RUN_ROOT/logs/time_0493x14e.txt"

python3 - "$STATE" "$NX" "$NY" "$GAMMA" "$MASS_TYPE1" "$MASS_TYPE2" "$TARGET_TYPE1" <<'PY'
import math,os,struct,sys
path,nx,ny,gamma,m1,m2,T=sys.argv[1:]
nx=int(nx); ny=int(ny); gamma=int(gamma); m1=float(m1); m2=float(m2); T=float(T)
per=gamma//2
# Opposite initial means with zero total momentum for M1/M2=10.
mean={1:(0.02,0.0),2:(-0.20,0.0)}
x=[];y=[];vx=[];vy=[];typ=[];mass=[];role=[]
for j in range(ny):
  for i in range(nx):
    for t,m in ((1,m1),(2,m2)):
      ux,uy=mean[t]; a=math.sqrt(2.0*(per-1)*T/(per*m))
      for k in range(per):
        th=2*math.pi*(k+0.5)/per; ph=th+(0.19 if t==2 else 0.0)
        x.append((i+0.5+0.30*math.cos(ph))/nx); y.append((j+0.5+0.30*math.sin(ph))/ny)
        vx.append(ux+a*math.cos(th)); vy.append(uy+a*math.sin(th)); typ.append(t); mass.append(m); role.append(1)
N=len(x); os.makedirs(os.path.dirname(path),exist_ok=True)
magic=b"SRCMPCD_STATE"+b"\0"*(16-len("SRCMPCD_STATE")); reserved=[0]*8; reserved[0]=1; reserved[1]=1
with open(path,"wb") as f:
  f.write(magic); f.write(struct.pack("<IIIIQIIII",2,0x01020304,2,1,N,1,1,8,4)); f.write(struct.pack("<8Q",*reserved))
  for arr,fmt in ((x,"d"),(y,"d"),(vx,"d"),(vy,"d"),(typ,"I"),(mass,"d"),(role,"B")):
    f.write(struct.pack(f"<{N}{fmt}",*arr))
print(f"[0493x14e-state] path={path} N={N} grid={nx}x{ny} gamma={gamma} masses={m1}/{m2}")
PY

cat > "$PARAMS" <<EOF
inputState = $STATE
outputDir = $RUN_ROOT/output
Lx = $Lx
Ly = $Ly
Nx = $NX
Ny = $NY
dt = $DT
nSteps = $STEPS
bodyAccelerationX = 0.0
bodyAccelerationY = 0.0
keepMeanFlowEnable = false
taylorGreenForcingEnable = false
bcLeft = periodic
bcRight = periodic
bcBottom = periodic
bcTop = periodic
bcX = periodic
bcY = periodic
speciesRegistryEnable = true
speciesCount = 2
species0 = 1 liquid liquid 0.0 1.0 $(python3 -c "print(($GAMMA//2)*float('$MASS_TYPE1'))")
species1 = 2 gas gas 0.0 1.0 $(python3 -c "print(($GAMMA//2)*float('$MASS_TYPE2'))")
speciesRequireRegisteredTypes = true
speciesDiagnosticsEnable = true
speciesDiagnosticsFilename = species_runtime_0493x14e.csv
speciesCellDiagnosticsEnable = false
speciesThermostatEnable = true
species0ThermostatTargetKBT = $TARGET_TYPE1
species1ThermostatTargetKBT = $TARGET_TYPE2
speciesQ6Enable = false
EOF
suite_write_common_params_0434 src >> "$PARAMS"

suite_export_cuda_flags_0434 src periodic
export MPCD_X12A_LOCAL_THERMAL_COOLING=0
export SRC_LIVE_VIS_ENABLE=0 MPCD_LIVE_VIS_ENABLE=0

echo "===== 0493x14e SRC per-type thermostat ====="
echo "PATHS: runner=$RUN_OK_ENTRYPOINT binary=$BIN state=$STATE params=$PARAMS output=$RUN_ROOT/output"
echo "GRID: L=${Lx}x${Ly} N=${NX}x${NY} gamma=$GAMMA dt=$DT steps=$STEPS gridShift=$GRID_SHIFT_ENABLE"
echo "SRC: angle=$ROTATION_ANGLE randomSign=$RANDOM_ROTATION_SIGN common two-type collision"
echo "THERMO: type1(m=$MASS_TYPE1,kBT=$TARGET_TYPE1) type2(m=$MASS_TYPE2,kBT=$TARGET_TYPE2) resident per-type CUDA"
echo "NOTE: ./livevis_control.kv is not modified"
suite_preflight_run_ok_0492 "$PARAMS"
if [[ "$PREFLIGHT_ONLY" == 1 ]]; then exit 0; fi
suite_ensure_binary_0434
/usr/bin/time -o "$TIMEFILE" -f 'elapsed=%e user=%U sys=%S' "$BIN" "$PARAMS" | tee "$LOG"
[[ -s "$FINAL" ]] || { echo "[0493x14e] FAIL missing final dump $FINAL" >&2; exit 3; }
python3 "$ROOT/tools/analyze_0493x14_species_thermostat_dynamic.py" \
  --initial "$STATE" --state "$FINAL" --species-csv "$RUN_ROOT/output/species_runtime_0493x14e.csv" \
  --label src_split --nx "$NX" --ny "$NY" --min-particles "$THERMOSTAT_MIN_PARTICLES" \
  --target1 "$TARGET_TYPE1" --target2 "$TARGET_TYPE2" --grid-shift 1
python3 - "$RUN_ROOT/output/cuda_persistent_src_collision_thermostat_0215.csv" <<'PY'
import csv,sys
p=sys.argv[1]
with open(p,newline='') as f: rows=list(csv.DictReader(f))
if not rows: raise SystemExit('[0493x14e] FAIL empty persistent collision/thermostat audit')
bad=[r for r in rows if int(r['thermostatAppliedOnGpu']) != 1]
if bad: raise SystemExit(f"[0493x14e] FAIL thermostatAppliedOnGpu !=1 on {len(bad)}/{len(rows)} rows")
if any(int(r['sharedParticleStateEnabled']) != 1 or int(r['sharedCellWorkspaceEnabled']) != 1 for r in rows):
  raise SystemExit('[0493x14e] FAIL resident shared particle/cell path not active')
print(f"[0493x14e] residentAudit PASS rows={len(rows)} thermostatAppliedOnGpu=1 sharedParticle=1 sharedCell=1")
PY
echo "[0493x14e] PASS SRC production-path species thermostat"
