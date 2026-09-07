#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_ok_common.sh"
suite_root_cd_0434

# 0493x14aj — n=3 two-phase oscillating-drop qualification of x14ai-fix1.
# Runner/tooling only: no C++/CUDA change and no new source diagnostic.
# The liquid modal observable q3 is reconstructed offline from sparse state dumps.

GENERATOR="$ROOT/scripts/generate_0493x14x_oscillating_drop_two_phase.py"
ANALYZER="$ROOT/scripts/analyze_0493x14aj_oscillating_drop_n3_two_phase.py"
SRC14V="$ROOT/src/cuda_q6_resident_0400.cu"
for f in "$GENERATOR" "$ANALYZER" "$SRC14V"; do
  [[ -f "$f" ]] || { echo "[0493x14aj] ERROR missing $f" >&2; exit 2; }
done
grep -q '0493x14ai — production-candidate device-side Q6 resultant closure' "$SRC14V" || {
  echo '[0493x14aj] ERROR x14ai source marker missing' >&2; exit 2;
}
grep -q 'B1-exact-post-periodic-device-target' "$SRC14V" || {
  echo '[0493x14aj] ERROR x14ai-fix1 post-periodic marker missing' >&2; exit 2;
}

CASE_LABEL="${CASE_LABEL:-0493x14aj_n3_device_q6_resultant_closure}"
RUN_MODE="src-q6-g-f"
TOPOLOGY="periodic"

# -----------------------------------------------------------------------------
# Physical/numerical parameters — deliberately visible in this runner.
# Same x14 fluid and geometry as the qualified n=2 benchmark; only n changes.
# -----------------------------------------------------------------------------
Lx="${Lx:-1.5625}"; Ly="${Ly:-1.5625}"; NX="${NX:-400}"; NY="${NY:-400}"
GAMMA="${GAMMA:-20}"
DT="${DT:-0.002}"
STEPS="${STEPS:-3000}"                  # 3.19 two-fluid n=3 periods
SEED="${SEED:-493180}"

RADIUS_CELLS="${RADIUS_CELLS:-40}"
MODE="${MODE:-3}"
EPSILON="${EPSILON:-0.04}"
PHASE="${PHASE:-0.0}"
CENTER_X="${CENTER_X:-0.78125}"; CENTER_Y="${CENTER_Y:-0.78125}"

LIQUID_TYPE="${LIQUID_TYPE:-1}"; GAS_TYPE="${GAS_TYPE:-2}"
LIQUID_MASS="${LIQUID_MASS:-1.0}"; GAS_MASS="${GAS_MASS:-0.1}"
LIQUID_KBT="${LIQUID_KBT:-0.02}"; GAS_KBT="${GAS_KBT:-0.08}"
KBT="${KBT:-$GAS_KBT}"
THERMOSTAT_TARGET_KBT="${THERMOSTAT_TARGET_KBT:-$GAS_KBT}"
THERMOSTAT_ENABLE="${THERMOSTAT_ENABLE:-true}"
THERMOSTAT_MODE="${THERMOSTAT_MODE:-cell_relative_rescale}"
THERMOSTAT_EVERY="${THERMOSTAT_EVERY:-1}"
THERMOSTAT_MIN_PARTICLES="${THERMOSTAT_MIN_PARTICLES:-3}"
ROTATION_ANGLE="${ROTATION_ANGLE:-1.5707963267948966}"
RANDOM_ROTATION_SIGN="${RANDOM_ROTATION_SIGN:-true}"
GRID_SHIFT_ENABLE="${GRID_SHIFT_ENABLE:-true}"

SURFACE_TENSION_SIGMA="${SURFACE_TENSION_SIGMA:-2560.0}"
SURFACE_TENSION_MIN_RADIUS_CELLS="${SURFACE_TENSION_MIN_RADIUS_CELLS:-4}"
PHASE_INTERFACE_KINETIC_REFLECTION_FRACTION="${PHASE_INTERFACE_KINETIC_REFLECTION_FRACTION:-1.0}"
PHASE_INTERFACE_EVAPORATION_TARGET_TYPE="${PHASE_INTERFACE_EVAPORATION_TARGET_TYPE:--1}"
PHASE_INTERFACE_CONTACT_ANGLE_DEG="${PHASE_INTERFACE_CONTACT_ANGLE_DEG:--1}"
X12A_LOCAL_THERMAL_RADIUS_CELLS="${X12A_LOCAL_THERMAL_RADIUS_CELLS:-25.298221281347036}"
PHASE_INTERFACE_A_SELECTOR="type:${LIQUID_TYPE}"; PHASE_INTERFACE_B_SELECTOR="type:${GAS_TYPE}"

LIQUID_Q6_STRENGTH="${LIQUID_Q6_STRENGTH:-1.0}"; GAS_Q6_STRENGTH="${GAS_Q6_STRENGTH:-0.0}"
SPECIES_Q6_MIN_FILL_FRACTION="${SPECIES_Q6_MIN_FILL_FRACTION:-0.10}"
Q6_GF_DENSITY_RELAXATION_TIME="${Q6_GF_DENSITY_RELAXATION_TIME:-0.25}"
Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE="${Q6_GF_DENSITY_COMPRESSION_GATE_ENABLE:-1}"
Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES="${Q6_GF_DENSITY_COMPRESSION_THRESHOLD_PARTICLES:-3.0}"
Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES="${Q6_GF_DENSITY_TRACTION_THRESHOLD_PARTICLES:-6.0}"
Q6_GF_DENSITY_TRACTION_GAIN="${Q6_GF_DENSITY_TRACTION_GAIN:-1.0}"
PROJECTION_BACKEND="${PROJECTION_BACKEND:-cuda}"
PROJECTION_MAX_ITERATIONS="${PROJECTION_MAX_ITERATIONS:-800}"
PROJECTION_TOLERANCE="${PROJECTION_TOLERANCE:-1.0e-5}"
Q6_PROJECTION_STRENGTH="${Q6_PROJECTION_STRENGTH:-1.0}"; Q6_STRICT="${Q6_STRICT:-1}"

# q3 needs particle-state snapshots. 125 steps -> ~7.5 samples/period and a final
# restart anchor exactly at step 3000, while avoiding the 10-step cadence of x13l.
SUMMARY_EVERY="${SUMMARY_EVERY:-10}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-125}"
FIT_PERIODS="${FIT_PERIODS:-2.5}"
NU_FIT_SCALE="${NU_FIT_SCALE:-0.00051}"  # fit search scale only, not gas/liquid damping theory

# General SRC run contract.
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
LIVE_VIS_CONTROL_FILE="$ROOT/livevis_control.kv"
LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-density}"
LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-1}"
LIVE_VIS_NX="${LIVE_VIS_NX:-200}"; LIVE_VIS_NY="${LIVE_VIS_NY:-200}"
LIVE_VIS_COLORMAP="${LIVE_VIS_COLORMAP:-hot}"
LIVE_VIS_CLIP="${LIVE_VIS_CLIP:--1}"; LIVE_VIS_GAIN="${LIVE_VIS_GAIN:-1.0}"
LIVE_VIS_SMOOTH_PASSES="${LIVE_VIS_SMOOTH_PASSES:-1}"
LIVE_VIS_WINDOW_SCALE="${LIVE_VIS_WINDOW_SCALE:-1}"
LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-1}"
RECORD_ENABLE="${RECORD_ENABLE:-true}"
RECORD_FIELDS="${RECORD_FIELDS:-mass,ux,uy}"
RECORD_EVERY="${RECORD_EVERY:-100}"
FILTER_MODE="${FILTER_MODE:-none}"
FILTER_SAMPLE_EVERY="${FILTER_SAMPLE_EVERY:-100}"
FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-1}"
PARTICLE_TYPE_FILTER="${PARTICLE_TYPE_FILTER:-1}"

# Restart is a separate segment; stochastic RNG restarts from SEED, as in the
# existing x14 qualification runners. Physical state is continued, trajectory is
# not promised bitwise-identical to an uninterrupted stochastic run.
RESTART="${RESTART:-0}"
RESTART_STATE="${RESTART_STATE:-}"
RESTART_TAG="${RESTART_TAG:-segment}"

BIN="${BIN:-${SRC_MPCD_DEFAULT_BIN_0434:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}}"
CAMPAIGN_ROOT="${CAMPAIGN_ROOT:-runs/0493x14aj_n3_device_q6_resultant_closure_seed${SEED}}"

GEN_CASE="tg"; U0=0.0; VELOCITY_MODE="zero"; PARTICLE_MASS="$GAS_MASS"
BACKGROUND_TYPE="$GAS_TYPE"; INACTIVE_TYPE="$GAS_TYPE"; TG_HOLE_ENABLE=false
SPECIES_RESAMPLING_ENABLE=false; SPECIES_RESIDENT_MODE=off
RESAMPLING_HOST_PATCHBACK_ENABLE=0; MASS_RECONDITION_ENABLE=0
RESAMPLING_THERMAL_RENORMALIZATION_ENABLE=false; RESAMPLING_MASS_GUARD_ENABLE=false
VIRIAL_DENSITY_KICK_ENABLE=false
Q6_GF_EXTERNAL_SPECIES=1; Q6_GF_HAS_GAS_PHASE=1
Q6_GF_MIN_FILL_FRACTION="$SPECIES_Q6_MIN_FILL_FRACTION"
RUN_OK_REFERENCE_PARTICLE_MASS="$LIQUID_MASS"
RUN_OK_GENERATOR_PATH="$GENERATOR"
export RUN_OK_REFERENCE_PARTICLE_MASS RUN_OK_GENERATOR_PATH

suite_defaults_common_0434
suite_compute_derived_0434

read -r H RADIUS AREA RHO_L RHO_G OMEGA0 PERIOD0 STEPS_PER_PERIOD P_REF <<<"$(python3 - \
 "$Lx" "$Ly" "$NX" "$NY" "$RADIUS_CELLS" "$GAMMA" "$LIQUID_MASS" "$GAS_MASS" \
 "$SURFACE_TENSION_SIGMA" "$MODE" "$EPSILON" "$DT" "$ROTATION_ANGLE" <<'PY'
import math,sys
lx,ly=float(sys.argv[1]),float(sys.argv[2]); nx,ny=int(sys.argv[3]),int(sys.argv[4])
rc,g,mL,mG,sigma=float(sys.argv[5]),float(sys.argv[6]),float(sys.argv[7]),float(sys.argv[8]),float(sys.argv[9])
n=int(sys.argv[10]); eps,dt,ang=float(sys.argv[11]),float(sys.argv[12]),float(sys.argv[13])
hx=lx/nx; hy=ly/ny
if abs(hx-hy)>1e-12*max(1.0,abs(hx),abs(hy)): raise SystemExit('[0493x14aj] square cells required')
if abs(hx-1/256)>1e-12: raise SystemExit(f'[0493x14aj] benchmark keeps characterized h=1/256, got {hx:.17g}')
if n!=3: raise SystemExit('[0493x14aj] this runner is intentionally MODE=3')
if not (0<eps<=0.05): raise SystemExit('[0493x14aj] require 0<epsilon<=0.05')
if abs(ang-math.pi/2)>1e-12: raise SystemExit('[0493x14aj] current x14 fluid uses rotationAngle=90deg')
R=rc*hx; A=hx*hy; rhoL=g*mL/A; rhoG=g*mG/A
w=math.sqrt(n*(n*n-1)*sigma/((rhoL+rhoG)*R**3)); T=2*math.pi/w
print(f'{hx:.17g} {R:.17g} {A:.17g} {rhoL:.17g} {rhoG:.17g} {w:.17g} {T:.17g} {T/dt:.17g} 0')
PY
)"
P_REF="$(awk -v g="$GAMMA" -v tg="$GAS_KBT" -v a="$AREA" 'BEGIN{printf "%.17g",g*tg/a}')"

if [[ "$RESTART" == "1" ]]; then
  [[ -n "$RESTART_STATE" && -s "$RESTART_STATE" ]] || { echo '[0493x14aj] ERROR RESTART=1 requires RESTART_STATE=/path/state_step_N.smpcd' >&2; exit 2; }
  RUN_ROOT="$CAMPAIGN_ROOT/restart_${RESTART_TAG}"
  STATE="$RESTART_STATE"
  CLEAN_RUN_ROOT=1
else
  RUN_ROOT="$CAMPAIGN_ROOT"
  STATE="$RUN_ROOT/init/${CASE_LABEL}.smpcd"
fi
if suite_truthy_0434 "$CLEAN_RUN_ROOT"; then rm -rf "$RUN_ROOT"; fi
suite_prepare_dirs_0434 "$RUN_ROOT"
OUT="$RUN_ROOT/output"; PARAMS="$RUN_ROOT/params/${CASE_LABEL}.kv"; LOG="$RUN_ROOT/logs/${CASE_LABEL}.log"; TF="$RUN_ROOT/logs/${CASE_LABEL}.time"; ANALYSIS_DIR="$RUN_ROOT/analysis"
mkdir -p "$OUT" "$ANALYSIS_DIR"

if [[ "$RESTART" != "1" ]]; then
  python3 "$GENERATOR" \
    --output "$STATE" --Lx "$Lx" --Ly "$Ly" --nx "$NX" --ny "$NY" --gamma "$GAMMA" \
    --center-x "$CENTER_X" --center-y "$CENTER_Y" --radius-cells "$RADIUS_CELLS" \
    --mode "$MODE" --epsilon "$EPSILON" --phase "$PHASE" \
    --liquid-type "$LIQUID_TYPE" --gas-type "$GAS_TYPE" \
    --liquid-mass "$LIQUID_MASS" --gas-mass "$GAS_MASS" \
    --liquid-kBT "$LIQUID_KBT" --gas-kBT "$GAS_KBT" --seed "$SEED"
fi

LREF="$(awk -v g="$GAMMA" -v m="$LIQUID_MASS" 'BEGIN{printf "%.17g",g*m}')"
GREF="$(awk -v g="$GAMMA" -v m="$GAS_MASS" 'BEGIN{printf "%.17g",g*m}')"
cat > "$PARAMS" <<PARAMS_EOF
inputState = $STATE
outputDir = $OUT
Lx = $Lx
Ly = $Ly
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
openBoundarySegmentsEnable = false
openBoundarySegmentCount = 0
bodyAccelerationX = 0.0
bodyAccelerationY = 0.0
taylorGreenForcingEnable = false
wallVpEnable = false
wallAccommodation = 1.0
wallThermalNoise = 0.0
speciesRegistryEnable = true
speciesCount = 2
species0 = $LIQUID_TYPE incompressible_liquid liquid $LIQUID_Q6_STRENGTH 1.0 $LREF
species0ResamplingEnable = false
species0ThermostatTargetKBT = $LIQUID_KBT
species1 = $GAS_TYPE compressible_gas gas $GAS_Q6_STRENGTH 0.0 $GREF
species1ResamplingEnable = false
species1ThermostatTargetKBT = $GAS_KBT
speciesRequireRegisteredTypes = true
speciesThermostatEnable = true
speciesDiagnosticsEnable = true
speciesDiagnosticsFilename = species_runtime_0493x14aj.csv
speciesCellDiagnosticsEnable = false
speciesQ6Sensitivity = 1.0
speciesQ6FallbackMode = common
speciesQ6ComparisonTolerance = 1.0e-11
PARAMS_EOF
suite_write_common_params_0434 "$RUN_MODE" >> "$PARAMS"
run_ok_surface_append_params_0493x13zi "$PARAMS" "$PHASE_INTERFACE_A_SELECTOR" "$PHASE_INTERFACE_B_SELECTOR"
cat >> "$PARAMS" <<'PARAMS_EOF'
phaseInterfaceKineticBilateralRelocation = true
PARAMS_EOF

suite_export_cuda_flags_0434 "$RUN_MODE" "$TOPOLOGY"
run_ok_surface_export_off_flags_0493x13zi
export MPCD_Q6_PHASE_GAS_PRESSURE_0493X6G=1
export MPCD_Q6_PHASE_GAS_PRESSURE_MODE_0493X6G=eos_accessible_volume
export MPCD_Q6_PHASE_GAS_PRESSURE_REFERENCE_0493X6G="$P_REF"
export MPCD_Q6_PHASE_GAS_PRESSURE_SCALE_0493X6G=1

# Qualified liquid chain unchanged.
export MPCD_X10O_Q6_THERMAL_INTERFACE_WALL=1
export MPCD_X10O_THERMAL_PARTICLE_MASS="$LIQUID_MASS"
export MPCD_X10O_THERMAL_SIGMAS="${X10O_THERMAL_SIGMAS:-3.0}"
export MPCD_X10O_THERMAL_MAX_CELLS="${X10O_THERMAL_MAX_CELLS:-0.75}"
export MPCD_X10_KINETIC_INTERFACE_CIC=1
export MPCD_X10_KINETIC_INTERFACE_QUADRATIC=1
export MPCD_X10P_INITIAL_OVERLAP_RESOLUTION=1
export MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE=1
export MPCD_X14L_GAS_SPECULAR_REFLECTION=1
export MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE_SWAP=1
export MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE_NORMAL_ONLY=0
export MPCD_X10_KINETIC_INTERFACE_THERMAL_PHASE_LIMITER=0
export MPCD_X12A_LOCAL_THERMAL_COOLING=1
export MPCD_X12A_LOCAL_THERMAL_RADIUS_CELLS="$X12A_LOCAL_THERMAL_RADIUS_CELLS"

# x14ad + x14ai-fix1 production candidate for closed/isolated liquid component.
export MPCD_X14V_GAS_KINETIC_EXCESS_KICK=1
export MPCD_X14V_SUBTRACT_X6G_THERMODYNAMIC_TRACTION=1
export MPCD_X14V_X6G_FACE_THERMO_TRACTION=0
export MPCD_X14V_X6G_GAUGE_FACE_THERMO_TRACTION=0
export MPCD_X14V_X6G_GAUGE_RESULTANT_PROJECTION=0
export MPCD_X14V_X6G_LOCAL_FACE_GAUGE_PROJECTION=1
export MPCD_X14V_REFERENCE_PRESSURE_GEOMETRIC_CLOSURE=0
export MPCD_X14V_SCATTER_LOSS_DIAGNOSTIC=0
export MPCD_X14V_GLOBAL_BALANCE_DIAGNOSTIC="${MPCD_X14V_GLOBAL_BALANCE_DIAGNOSTIC:-0}"
export MPCD_X14V_DEVICE_APPLIED_Q6_RESULTANT_CLOSURE=1

# Existing diagnostics only. n=3 uses offline q3, not x9f ellipse/q2.
export MPCD_Q6_ELLIPSE_DIAGNOSTICS_0493X9F=0
export MPCD_Q6_STATIC_DROP_DIAGNOSTICS_0493X9E=1
export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9A=0
export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9B=0
export MPCD_Q6_PHASE_CURVATURE_DIAGNOSTICS_0493X9C=0
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WORKSPACE_DOWNLOAD_0272=1

suite_prepare_livevis_control_0434 "$RUN_ROOT" "$RUN_MODE"
suite_export_livevis_0434
suite_write_env_file_0434 "$RUN_ROOT/logs/environment_0493x14aj.env" "$RUN_MODE"
cat >> "$RUN_ROOT/logs/environment_0493x14aj.env" <<META
BENCHMARK=0493x14aj_two_phase_oscillating_drop_n3
MODE=$MODE
EPSILON=$EPSILON
RADIUS_CELLS=$RADIUS_CELLS
RADIUS=$RADIUS
RHO_L=$RHO_L
RHO_G=$RHO_G
RHO_G_OVER_RHO_L=$(awk -v a="$RHO_G" -v b="$RHO_L" 'BEGIN{printf "%.17g",a/b}')
OMEGA_2D_TWO_FLUID=$OMEGA0
PERIOD_2D_TWO_FLUID=$PERIOD0
STEPS_PER_PERIOD=$STEPS_PER_PERIOD
SURFACE_TENSION_SIGMA=$SURFACE_TENSION_SIGMA
MPCD_X14V_X6G_LOCAL_FACE_GAUGE_PROJECTION=1
MPCD_X14V_DEVICE_APPLIED_Q6_RESULTANT_CLOSURE=1
RESTART=$RESTART
RESTART_STATE=$RESTART_STATE
META

echo
echo "===== 0493x14aj TWO-PHASE OSCILLATING DROP n=3 ====="
echo "PATHS: runner=$ROOT/scripts/run_0493x14aj_oscillating_drop_n3_device_closure.sh"
echo "       generator=$GENERATOR analyzer=$ANALYZER"
echo "       state=$STATE params=$PARAMS output=$OUT"
echo "GEOM:  periodic ${NX}x${NY}, h=$H, R/h=$RADIUS_CELLS, n=$MODE, eps=$EPSILON"
echo "PHASE: liquid(type=$LIQUID_TYPE,m=$LIQUID_MASS,kBT=$LIQUID_KBT,q6=$LIQUID_Q6_STRENGTH)"
echo "       gas(type=$GAS_TYPE,m=$GAS_MASS,kBT=$GAS_KBT,q6=$GAS_Q6_STRENGTH)"
echo "CHAIN: x6g + x9 + x14l + x14v + x14ad local traction + x14ai-fix1 global resultant"
echo "       liquid x10o/CIC/Q2/x10p/q/x10u/x10v/x12a UNCHANGED"
echo "THEORY: rhoL=$RHO_L rhoG=$RHO_G omega3(two-fluid)=$OMEGA0 period=$PERIOD0 steps/period=$STEPS_PER_PERIOD"
echo "RUN:   steps=$STEPS dt=$DT tEnd=$(awk -v n="$STEPS" -v d="$DT" 'BEGIN{printf "%.9g",n*d}') summaryEvery=$SUMMARY_EVERY dumpEvery=$DUMP_STATE_EVERY"
echo "VIS:   enable=$LIVE_VIS_ENABLE every=$LIVE_VIS_EVERY record=$RECORD_ENABLE recordEvery=$RECORD_EVERY"
echo "NOTE:  q3 reconstructed offline from liquid particles; ./livevis_control.kv is not modified"
echo "========================================================"

suite_run_binary_0434 "$PARAMS" "$LOG" "$TF" "$OUT"
if suite_truthy_0434 "$PREFLIGHT_ONLY"; then echo '[0493x14aj] PREFLIGHT_ONLY complete'; exit 0; fi

grep -q 'deviceAppliedQ6ResultantClosure=B1-exact-post-periodic-device-target' "$LOG" || {
  echo '[0493x14aj] ERROR expected x14ai-fix1 runtime marker absent' >&2; exit 2;
}

# Build a small liquid-only view of the sparse state dumps for q3 analysis.
FILTERED_ROOT="$ANALYSIS_DIR/liquid_only_modal_view"
python3 - "$OUT" "$FILTERED_ROOT/output" "$LIQUID_TYPE" <<'PY'
import re, shutil, struct, sys
from array import array
from pathlib import Path
MAGIC=b"SRCMPCD_STATE"+b"\0"*(16-len("SRCMPCD_STATE")); STEP_RE=re.compile(r"state_step_(\d+)\.smpcd$")
def ra(f,c,n):
    a=array(c); a.fromfile(f,n)
    if len(a)!=n: raise RuntimeError("truncated state array")
    return a
def ws(path,x,y,vx,vy,typ,mass,role):
    n=len(x); path.parent.mkdir(parents=True,exist_ok=True)
    with path.open('wb') as f:
        f.write(MAGIC); f.write(struct.pack('<IIIIQIIII',2,0x01020304,2,1,n,1,1,0,4))
        for a in (x,y,vx,vy,typ,mass): a.tofile(f)
        f.write(role)
src=Path(sys.argv[1]); dst=Path(sys.argv[2]); lt=int(sys.argv[3])
if dst.exists(): shutil.rmtree(dst)
dst.mkdir(parents=True,exist_ok=True); written=0
for p in sorted(src.glob('state_step_*.smpcd')):
    if not STEP_RE.search(p.name): continue
    with p.open('rb') as f:
        if f.read(16)!=MAGIC: raise RuntimeError(f'{p}: bad state magic')
        version,endian,dim,layout,n,ht,hm,res,type_bytes=struct.unpack('<IIIIQIIII',f.read(40))
        if version!=2 or endian!=0x01020304 or dim!=2 or layout!=1 or not ht or not hm or type_bytes!=4: raise RuntimeError(f'{p}: unsupported state header')
        if res: f.read(8*res)
        x0=ra(f,'d',n); y0=ra(f,'d',n); vx0=ra(f,'d',n); vy0=ra(f,'d',n); t0=ra(f,'I',n); m0=ra(f,'d',n); r0=ra(f,'B',n)
    keep=[i for i,t in enumerate(t0) if int(t)==lt and r0[i]==1]
    x=array('d',(x0[i] for i in keep)); y=array('d',(y0[i] for i in keep)); vx=array('d',(vx0[i] for i in keep)); vy=array('d',(vy0[i] for i in keep)); typ=array('I',(t0[i] for i in keep)); mass=array('d',(m0[i] for i in keep)); role=bytearray([1]*len(keep))
    ws(dst/p.name,x,y,vx,vy,typ,mass,role); written+=1
print(f'[0493x14aj-filter] liquid dumps={written} source={src} filteredRoot={dst.parent}')
PY

python3 "$ANALYZER" \
  --run-root "$FILTERED_ROOT" --radius-cells "$RADIUS_CELLS" --sigma "$SURFACE_TENSION_SIGMA" \
  --gamma "$GAMMA" --liquid-mass "$LIQUID_MASS" --gas-mass "$GAS_MASS" --h "$H" \
  --nu-fit-scale "$NU_FIT_SCALE" --dt "$DT" --mode "$MODE" --phase "$PHASE" --fit-periods "$FIT_PERIODS"

# Copy compact analysis products to the main analysis directory.
cp -f "$FILTERED_ROOT/analysis_0493x14aj/"* "$ANALYSIS_DIR/" 2>/dev/null || true

# Existing species diagnostics: quantify rare total-momentum jumps without adding instrumentation.
python3 - "$OUT/species_runtime_0493x14aj.csv" "$ANALYSIS_DIR/momentum_monitor_0493x14aj.json" <<'PY'
import csv,json,math,sys
from collections import defaultdict
src,dst=sys.argv[1],sys.argv[2]
by=defaultdict(lambda:[0.0,0.0])
with open(src,newline='') as f:
    for r in csv.DictReader(f):
        s=int(r['step']); by[s][0]+=float(r['Px']); by[s][1]+=float(r['Py'])
steps=sorted(by)
p0=by[steps[0]]; pend=by[steps[-1]]
maxjump=(-1.0,None,0.0,0.0); maxdrift=0.0
prev=None
for s in steps:
    p=by[s]
    maxdrift=max(maxdrift,math.hypot(p[0]-p0[0],p[1]-p0[1]))
    if prev is not None:
        dx=p[0]-prev[1][0]; dy=p[1]-prev[1][1]; n=math.hypot(dx,dy)
        if n>maxjump[0]: maxjump=(n,s,dx,dy)
    prev=(s,p)
out={'samples':len(steps),'firstStep':steps[0],'lastStep':steps[-1],'P0':p0,'Pend':pend,'maxDriftFromP0':maxdrift,'maxSampleToSampleJump':maxjump[0],'maxJumpEndStep':maxjump[1],'maxJumpVector':[maxjump[2],maxjump[3]]}
open(dst,'w').write(json.dumps(out,indent=2,sort_keys=True)+'\n')
print('[0493x14aj-momentum]',json.dumps(out,sort_keys=True))
PY

if [[ -s "$OUT/cuda_phase_interface_pressure_0493x6g.csv" && -s "$OUT/cuda_phase_interface_stencil_0493x6f.csv" ]]; then
  python3 "$ROOT/scripts/analyze_0493x6g_phase_gas_pressure.py" \
    --pressure "$OUT/cuda_phase_interface_pressure_0493x6g.csv" \
    --stencil "$OUT/cuda_phase_interface_stencil_0493x6f.csv" \
    --json "$ANALYSIS_DIR/phase_interface_gas_pressure_0493x14aj.json" || true
fi

OUT_TAR="$RUN_ROOT/0493x14aj_two_phase_oscillating_drop_n3_compact.tar.gz"
FILES=(analysis \
 "output/species_runtime_0493x14aj.csv" \
 "output/cuda_phase_interface_pressure_0493x6g.csv" \
 "output/cuda_phase_interface_stencil_0493x6f.csv" \
 "output/cuda_surface_tension_limiter_0493x9r.csv" \
 "output/cuda_phase_kinetic_crossing_0493x9z.csv" \
 "output/cuda_species_q6_independent_masked_0493w5.csv" \
 "output/cuda_species_q6_0491.csv" \
 "logs/${CASE_LABEL}.log" "logs/${CASE_LABEL}.time" "logs/environment_0493x14aj.env" \
 "params/${CASE_LABEL}.kv")
EXIST=(); for f in "${FILES[@]}"; do [[ -e "$RUN_ROOT/$f" ]] && EXIST+=("$f"); done
tar -czf "$OUT_TAR" -C "$RUN_ROOT" "${EXIST[@]}"

echo
echo "[0493x14aj] DONE"
echo "[0493x14aj] q3 summary: $ANALYSIS_DIR/oscillating_drop_n3_two_phase_summary_0493x14aj.json"
echo "[0493x14aj] momentum:   $ANALYSIS_DIR/momentum_monitor_0493x14aj.json"
echo "[0493x14aj] return:     $OUT_TAR"
