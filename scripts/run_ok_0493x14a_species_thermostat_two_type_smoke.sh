#!/usr/bin/env bash
set -euo pipefail

# 0493x14a — two-type thermostat smoke.
# Purpose:
#   1) validate type-local cell_relative_rescale targets on the Q6-resident CUDA path;
#   2) verify per-type momentum preservation when SRC rotation is disabled;
#   3) verify the expected thermal-speed ratio for m1/m2=10.
# This runner never creates, rewrites or normalizes ./livevis_control.kv.

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_ok_common.sh"
suite_root_cd_0434

RUN_OK_ENTRYPOINT="$ROOT/scripts/run_0493x14a_species_thermostat_two_type_smoke.sh"
CASE_LABEL="species_thermostat_two_type_0493x14a"
BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}"
RUN_ROOT="${RUN_ROOT:-runs/0493x14a_species_thermostat_two_type_smoke}"
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"

NX="${NX:-8}"
NY="${NY:-4}"
GAMMA="${GAMMA:-8}"          # 4 particles of each type per cell
DT="${DT:-1.0e-4}"
STEPS="${STEPS:-1}"
SEED="${SEED:-493130}"
THREADS="${THREADS:-8}"
MASS_TYPE1="${MASS_TYPE1:-1.0}"
MASS_TYPE2="${MASS_TYPE2:-0.1}"
TARGET_EQUAL="${TARGET_EQUAL:-0.02}"
TARGET_SPLIT_1="${TARGET_SPLIT_1:-0.02}"
TARGET_SPLIT_2="${TARGET_SPLIT_2:-0.08}"
THERMOSTAT_MIN_PARTICLES="${THERMOSTAT_MIN_PARTICLES:-3}"
TOL="${TOL:-2.0e-10}"

if (( GAMMA < 8 || GAMMA % 2 != 0 )); then
  echo "[0493x14a] ERROR GAMMA must be even and >=8" >&2
  exit 2
fi

export LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
export OMP_NUM_THREADS="$THREADS"

# Explicit physical/numerical parameters used by suite_write_common_params_0434.
Lx=1.0
Ly=1.0
KBT="$TARGET_EQUAL"             # legacy/global fallback only
PARTICLE_MASS="$MASS_TYPE1"
ROTATION_ANGLE=0.0              # collision stage is a no-op for the smoke
RANDOM_ROTATION_SIGN=false
GRID_SHIFT_ENABLE=false
THERMOSTAT_ENABLE=true
THERMOSTAT_MODE=cell_relative_rescale
THERMOSTAT_EVERY=1
THERMOSTAT_TARGET_KBT="$TARGET_EQUAL"
SUMMARY_EVERY=1
DUMP_STATE_EVERY=1000000
DUMP_ROLE_FILTER=fluid
SUMMARY_ROLE_FILTER=fluid
INACTIVE_SLOTS=0
U0=0.0
UIN=0.0
PROJECTION_BACKEND=cuda
PROJECTION_OPERATOR=auto_fv_cg
PROJECTION_MAX_ITERATIONS=100
PROJECTION_TOLERANCE=1.0e-12
PROJECTION_MOMENTUM_CORRECTION_ENABLE=true
Q6_PROJECTION_STRENGTH=0.0             # keep Q6 resident plumbing active without changing velocities
SPECIES_RESAMPLING_ENABLE=false
WEIGHTED_RESAMPLING_ENABLE_OVERRIDE=false
CUDA_EMPTY_REFILL_ENABLE_OVERRIDE=false
RESAMPLING_THERMAL_RENORMALIZATION_ENABLE=false
RESAMPLING_MASS_GUARD_ENABLE=false
CUDA_RESAMPLING_CHI_FILTER_ENABLE=false
CUDA_RESAMPLING_CHI_MIN=0.05
GUARD_NMIN=$((GAMMA - 2))
GUARD_NTARGET="$GAMMA"
GUARD_NMAX=$((GAMMA + 2))
LIVE_VIS_ENABLE=0
FILTERED_RECORDING_ENABLE=0
RECORD_ENABLE=false
PARTICLE_TYPE_FILTER=-1

suite_defaults_common_0434
suite_compute_derived_0434

if [[ "$CLEAN_RUN_ROOT" == 1 && "$PREFLIGHT_ONLY" != 1 ]]; then
  rm -rf "$RUN_ROOT"
fi
mkdir -p "$RUN_ROOT/init" "$RUN_ROOT/logs"

STATE="$RUN_ROOT/init/two_type_uniform_0493x14a.smpcd"

make_state() {
  python3 - "$STATE" "$NX" "$NY" "$GAMMA" "$MASS_TYPE1" "$MASS_TYPE2" <<'PY'
import math, os, struct, sys
path, nx, ny, gamma, m1, m2 = sys.argv[1:]
nx, ny, gamma = int(nx), int(ny), int(gamma)
m1, m2 = float(m1), float(m2)
per = gamma // 2
x=[]; y=[]; vx=[]; vy=[]; typ=[]; mass=[]; role=[]
# Same type-local mean in every cell. The four-direction thermal pattern has
# exactly zero type-local momentum in each cell before thermostatting.
mean = {1:(0.15,-0.05), 2:(-0.10,0.08)}
amp  = {1:0.17, 2:0.41}
for j in range(ny):
    for i in range(nx):
        for t, m in ((1,m1),(2,m2)):
            ux, uy = mean[t]
            a = amp[t]
            for k in range(per):
                th = 2.0*math.pi*(k+0.5)/per
                # keep both types spatially interleaved inside the same cell
                ph = th + (0.23 if t == 2 else 0.0)
                x.append((i + 0.5 + 0.28*math.cos(ph))/nx)
                y.append((j + 0.5 + 0.28*math.sin(ph))/ny)
                vx.append(ux + a*math.cos(th))
                vy.append(uy + a*math.sin(th))
                typ.append(t); mass.append(m); role.append(1)
N=len(x)
os.makedirs(os.path.dirname(path), exist_ok=True)
magic=b"SRCMPCD_STATE" + b"\0"*(16-len("SRCMPCD_STATE"))
reserved=[0]*8; reserved[0]=1; reserved[1]=1
with open(path,"wb") as f:
    f.write(magic)
    f.write(struct.pack("<IIIIQIIII",2,0x01020304,2,1,N,1,1,8,4))
    f.write(struct.pack("<8Q",*reserved))
    for arr,fmt in [(x,"d"),(y,"d"),(vx,"d"),(vy,"d"),(typ,"I"),(mass,"d"),(role,"B")]:
        f.write(struct.pack(f"<{N}{fmt}",*arr))
print(f"[0493x14a-state] path={path} grid={nx}x{ny} gamma={gamma} typeCount={per}/{per} masses={m1}/{m2} N={N}")
PY
}

write_params() {
  local case_dir=$1 target1=$2 target2=$3
  local params="$case_dir/params/params_0493x14a.kv"
  mkdir -p "$case_dir/params" "$case_dir/output" "$case_dir/logs"
  KBT="$TARGET_EQUAL"
  THERMOSTAT_TARGET_KBT="$TARGET_EQUAL"
  cat > "$params" <<EOF
inputState = $STATE
outputDir = $case_dir/output
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
species0 = 1 liquid liquid 1.0 1.0 $(python3 -c "print(($GAMMA//2)*float('$MASS_TYPE1'))")
species1 = 2 gas gas 0.0 1.0 $(python3 -c "print(($GAMMA//2)*float('$MASS_TYPE2'))")
speciesRequireRegisteredTypes = true
speciesDiagnosticsEnable = true
speciesDiagnosticsFilename = species_runtime_0493x14a.csv
speciesThermostatEnable = true
species0ThermostatTargetKBT = $target1
species1ThermostatTargetKBT = $target2
speciesQ6Enable = false
speciesQ6Mode = common
EOF
  suite_write_common_params_0434 src-q6 >> "$params"
  printf '%s\n' "$params"
}

analyze_case() {
  local label=$1 csv=$2 target1=$3 target2=$4 expected_ratio=$5
  python3 - "$label" "$csv" "$target1" "$target2" "$expected_ratio" "$MASS_TYPE1" "$MASS_TYPE2" "$TOL" "$NX" "$NY" "$GAMMA" <<'PY'
import csv, math, sys
label, path = sys.argv[1], sys.argv[2]
targets={1:float(sys.argv[3]),2:float(sys.argv[4])}
expected_ratio=float(sys.argv[5]); masses={1:float(sys.argv[6]),2:float(sys.argv[7])}; tol=float(sys.argv[8])
nx, ny, gamma = int(sys.argv[9]), int(sys.argv[10]), int(sys.argv[11])
per_type_per_cell = gamma // 2
occupied_cells = nx * ny
expected_mean={1:(0.15,-0.05),2:(-0.10,0.08)}
rows=[]
with open(path,newline='') as f:
    rows=list(csv.DictReader(f))
steps=max(int(r['step']) for r in rows)
final={int(r['type']):r for r in rows if int(r['step'])==steps and int(r['type']) in (1,2)}
if set(final)!={1,2}: raise SystemExit(f"[0493x14a] FAIL {label}: missing final species rows")
vrms={}
for t in (1,2):
    r=final[t]; N=int(r['nFluid']); M=float(r['totalMass']); ke=float(r['kineticEnergy']); ux=float(r['meanVx']); uy=float(r['meanVy'])
    krel=ke-0.5*M*(ux*ux+uy*uy)
    expected_n = occupied_cells * per_type_per_cell
    if N != expected_n:
        raise SystemExit(f"[0493x14a] FAIL {label} type={t}: smoke state occupancy changed N={N} expected={expected_n}")
    # cell_relative_rescale removes the two components of the type-local
    # center-of-mass velocity independently in every occupied cell. In 2-D,
    # K_target(cell)=(n_cell-1)*kBT, hence globally
    # K_rel=(N-N_occupied_cells)*kBT for this uniform smoke.
    dof_half = N - occupied_cells
    kbt=krel/dof_half if dof_half>0 else 0.0
    err=abs(kbt-targets[t])
    if err > tol*max(1.0,abs(targets[t])):
        raise SystemExit(f"[0493x14a] FAIL {label} type={t}: kBT={kbt:.17g} target={targets[t]:.17g} err={err:.3e}")
    ex,ey=expected_mean[t]
    if abs(ux-ex)>tol or abs(uy-ey)>tol:
        raise SystemExit(f"[0493x14a] FAIL {label} type={t}: thermostat/collision path changed type momentum meanV=({ux:.17g},{uy:.17g}) expected=({ex:.17g},{ey:.17g})")
    vrms[t]=math.sqrt(max(0.0,2.0*krel/M))
    print(f"[0493x14a] {label} type={t} kBT={kbt:.12g} target={targets[t]:.12g} dofHalf={dof_half} meanV=({ux:.12g},{uy:.12g}) vrelRms={vrms[t]:.12g}")
ratio=vrms[2]/vrms[1]
rel=abs(ratio/expected_ratio-1.0)
if rel > 2e-10:
    raise SystemExit(f"[0493x14a] FAIL {label}: vrelRms ratio={ratio:.17g} expected={expected_ratio:.17g} rel={rel:.3e}")
print(f"[0493x14a] PASS {label}: vrelRms2/vrelRms1={ratio:.12g} expected={expected_ratio:.12g}")
PY
}

make_state
if [[ "$PREFLIGHT_ONLY" != 1 ]]; then suite_ensure_binary_0434; fi

run_one() {
  local label=$1 t1=$2 t2=$3 expected=$4
  local dir="$RUN_ROOT/$label" params log time_file
  params="$(write_params "$dir" "$t1" "$t2")"
  log="$dir/logs/run_0493x14a.log"
  time_file="$dir/logs/time_0493x14a.txt"

  # Q6 resident thermostat is the production path targeted by this patch.
  suite_export_cuda_flags_0434 src-q6 periodic
  export MPCD_X12A_LOCAL_THERMAL_COOLING=0
  export SRC_LIVE_VIS_ENABLE=0 MPCD_LIVE_VIS_ENABLE=0

  echo "===== 0493x14a $label ====="
  echo "PATHS: runner=$RUN_OK_ENTRYPOINT binary=$BIN state=$STATE params=$params output=$dir/output"
  echo "GRID:  L=${Lx}x${Ly} N=${NX}x${NY} gamma=$GAMMA dt=$DT steps=$STEPS rotation=$ROTATION_ANGLE gridShift=$GRID_SHIFT_ENABLE"
  echo "TYPES: type1 mass=$MASS_TYPE1 kBT=$t1 ; type2 mass=$MASS_TYPE2 kBT=$t2 ; thermostatMinParticles=$THERMOSTAT_MIN_PARTICLES"
  echo "PATH:  collision=common SRC/MPCD ; thermostat=per-type cell_relative_rescale ; Q6-resident thermostat=1 ; x12a=OFF"
  echo "NOTE:  ./livevis_control.kv is not modified by this runner"
  suite_preflight_run_ok_0492 "$params"
  if [[ "$PREFLIGHT_ONLY" == 1 ]]; then return 0; fi
  /usr/bin/time -o "$time_file" -f 'elapsed=%e user=%U sys=%S' "$BIN" "$params" | tee "$log"
  analyze_case "$label" "$dir/output/species_runtime_0493x14a.csv" "$t1" "$t2" "$expected"
}

# Equal kinetic temperatures: m2=m1/10 -> thermal speed ratio sqrt(10).
RATIO_EQUAL=$(python3 -c "import math; print(math.sqrt(float('$MASS_TYPE1')/float('$MASS_TYPE2')))")
run_one equal_temperature "$TARGET_EQUAL" "$TARGET_EQUAL" "$RATIO_EQUAL"

# Distinct kinetic targets: ratio sqrt((T2/m2)/(T1/m1)).
RATIO_SPLIT=$(python3 -c "import math; print(math.sqrt((float('$TARGET_SPLIT_2')/float('$MASS_TYPE2'))/(float('$TARGET_SPLIT_1')/float('$MASS_TYPE1'))))")
run_one split_temperature "$TARGET_SPLIT_1" "$TARGET_SPLIT_2" "$RATIO_SPLIT"

if [[ "$PREFLIGHT_ONLY" != 1 ]]; then
  echo "[0493x14a] PASS all two-type thermostat smokes"
fi
