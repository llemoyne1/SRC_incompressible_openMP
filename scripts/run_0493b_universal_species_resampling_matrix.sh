#!/usr/bin/env bash
set -uo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434

CASE_LABEL="universal_species_resampling_matrix"
BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}"
RUN_ROOT="${RUN_ROOT:-runs/0493b_universal_species_resampling_matrix}"
NX="${NX:-12}"
NY="${NY:-8}"
GAMMA="${GAMMA:-6}"
STEPS="${STEPS:-5}"
DT="${DT:-0.005}"
KBT="${KBT:-0.005}"
SEED="${SEED:-49302}"
SUMMARY_EVERY="${SUMMARY_EVERY:-1}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-0}"
UIN="${UIN:-0.03}"
THREADS="${THREADS:-4}"
PARTICLE_MASS="${PARTICLE_MASS:-1.0}"
SOLVENT_MASS="${SOLVENT_MASS:-1.0}"
COLLOID_MASS="${COLLOID_MASS:-6.0}"
INACTIVE_SLOTS_CELL_FRACTION="${INACTIVE_SLOTS_CELL_FRACTION:-2.0}"
GUARD_NMIN="${GUARD_NMIN:-5}"
GUARD_NTARGET="${GUARD_NTARGET:-6}"
GUARD_NMAX="${GUARD_NMAX:-7}"
GUARD_EVERY="${GUARD_EVERY:-1}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
LIVE_VIS_ENABLE=0
LIVE_VIS_CONTROL_FILE="${LIVE_VIS_CONTROL_FILE:-$ROOT/livevis_control.kv}"
OVERWRITE_LIVEVIS_CONTROL=0
SPECIES_RESAMPLING_ENABLE=true
SPECIES_RESIDENT_MODE=production
RESAMPLING_HOST_PATCHBACK_ENABLE=0
RESAMPLING_SPARSE_DEVICE_GATE_ENABLE=0
RESAMPLING_THERMAL_RENORMALIZATION_ENABLE=false
RESAMPLING_MASS_GUARD_ENABLE=false
MASS_RECONDITION_ENABLE=0
THERMOSTAT_ENABLE=true
THERMOSTAT_MODE=cell_relative_rescale
THERMOSTAT_EVERY=1
THERMOSTAT_TARGET_KBT="$KBT"
THERMOSTAT_MIN_PARTICLES=2
PROJECTION_BACKEND=cuda
PROJECTION_OPERATOR=auto_fv_cg
PROJECTION_MAX_ITERATIONS=250
PROJECTION_TOLERANCE=1.0e-11
PROJECTION_MOMENTUM_CORRECTION_ENABLE=true
Q6_PROJECTION_STRENGTH=1.0
ROTATION_ANGLE=2.0943951023931953
RANDOM_ROTATION_SIGN=true
GRID_SHIFT_ENABLE=true
SUMMARY_ROLE_FILTER=fluid
DUMP_ROLE_FILTER=fluid
CUDA_RESAMPLING_CHI_FILTER_ENABLE=false
CUDA_RESAMPLING_CHI_MIN=0.05
RESAMPLING_EXTRACTION_ENABLE=true
RESAMPLING_INSERTION_ENABLE=true
RESAMPLING_REMAP_ENABLE=true
RESAMPLING_PARTICLE_MASS_MIN=0.1
RESAMPLING_PARTICLE_MASS_MAX=20.0
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"

export LIVE_PROGRESS
suite_defaults_common_0434
suite_compute_derived_0434

if (( GAMMA < 4 )); then
  echo "[0493b-matrix] ERROR GAMMA must be >=4" >&2
  exit 2
fi
if [[ "$CLEAN_RUN_ROOT" == 1 ]]; then rm -rf "$RUN_ROOT"; fi
mkdir -p "$RUN_ROOT/init" "$RUN_ROOT/logs"

# Compile or refresh the binary once. Individual cases launch the same binary directly.
if [[ "$PREFLIGHT_ONLY" != 1 ]]; then
  suite_ensure_binary_0434
fi

STATE="$RUN_ROOT/init/two_species_0493b.smpcd"
python3 - "$STATE" "$NX" "$NY" "$GAMMA" "$SOLVENT_MASS" "$COLLOID_MASS" "$INACTIVE_SLOTS_CELL_FRACTION" <<'PY_STATE'
import os, struct, sys
path, nx, ny, gamma, ms, mc, inactive_fraction = sys.argv[1:]
nx, ny, gamma = int(nx), int(ny), int(gamma)
ms, mc, inactive_fraction = float(ms), float(mc), float(inactive_fraction)
x=[]; y=[]; vx=[]; vy=[]; typ=[]; mass=[]; role=[]
for j in range(ny):
    for i in range(nx):
        c=j*nx+i
        n = gamma + (2 if c == 0 else (-2 if c == 1 else 0))
        for k in range(n):
            x.append((i + (k + 0.5)/n)/nx)
            y.append((j + ((3*k+1) % n + 0.5)/n)/ny)
            vx.append(0.01 * ((c % 3) - 1))
            vy.append(0.005 * (((c+1) % 3) - 1))
            if k % 2 == 0:
                typ.append(1); mass.append(ms)
            else:
                typ.append(2); mass.append(mc)
            role.append(1)
active = len(x)
inactive = max(1, int(round(nx * ny * inactive_fraction)))
for k in range(inactive):
    x.append(0.0); y.append(0.0); vx.append(0.0); vy.append(0.0)
    typ.append(0); mass.append(1.0); role.append(0)
os.makedirs(os.path.dirname(path), exist_ok=True)
magic=b"SRCMPCD_STATE"+b"\0"*(16-len("SRCMPCD_STATE"))
reserved=[0]*8; reserved[0]=1; reserved[1]=1
N=len(x)
with open(path,"wb") as f:
    f.write(magic)
    f.write(struct.pack("<IIIIQIIII",2,0x01020304,2,1,N,1,1,8,4))
    f.write(struct.pack("<8Q",*reserved))
    for arr,fmt in [(x,"d"),(y,"d"),(vx,"d"),(vy,"d"),(typ,"I"),(mass,"d"),(role,"B")]:
        f.write(struct.pack(f"<{N}{fmt}",*arr))
print(f"[0493b-state] path={path} fluid={active} inactive={inactive} capacity={N} cells={nx*ny} gamma={gamma}")
PY_STATE

write_topology_0493b() {
  local topology=$1 params=$2
  case "$topology" in
    periodic)
      cat >> "$params" <<'EOF'
bcLeft = periodic
bcRight = periodic
bcBottom = periodic
bcTop = periodic
bcX = periodic
bcY = periodic
EOF
      ;;
    wall)
      cat >> "$params" <<EOF
bcLeft = periodic
bcRight = periodic
bcBottom = solid
bcTop = solid
bcX = periodic
bcY = wall
wallAccommodation = 1.0
wallThermalNoise = 0.0
wallKBT = -1.0
wallVpGamma = $GAMMA
wallVpMass = $PARTICLE_MASS
EOF
      ;;
    io_fullface)
      cat >> "$params" <<EOF
bcLeft = inlet
bcRight = outlet
bcBottom = solid
bcTop = solid
bcX = open
bcY = wall
inletUxLeft = $UIN
inletUyLeft = 0.0
inletInjectionMode = hard_cell_density
inletReservoirMode = hard_cell_density
inletReservoirCells = 1
inletTargetOccupancy = $GAMMA
inletVelocitySpatialProfile = uniform
inletThermalNoise = 0.0
inletKBT = -1.0
openBoundaryOutletMode = balanced_flux
wallAccommodation = 1.0
wallThermalNoise = 0.0
wallKBT = -1.0
wallVpGamma = $GAMMA
wallVpMass = $PARTICLE_MASS
EOF
      ;;
    segmented)
      cat >> "$params" <<EOF
bcLeft = solid
bcRight = solid
bcBottom = solid
bcTop = solid
bcX = wall
bcY = wall
openBoundarySegmentsEnable = true
openBoundarySegmentCount = 2
openBoundarySegment0 = left inlet 0.25 0.75 $UIN 0.0 1 $SOLVENT_MASS
openBoundarySegment1 = right outlet 0.0 1.0 $UIN 0.0 0 $PARTICLE_MASS
inletInjectionMode = hard_cell_density
inletReservoirMode = hard_cell_density
inletReservoirCells = 1
inletTargetOccupancy = $GAMMA
inletVelocitySpatialProfile = uniform
inletThermalNoise = 0.0
inletKBT = -1.0
openBoundaryOutletMode = hybrid
wallAccommodation = 1.0
wallThermalNoise = 0.0
wallKBT = -1.0
wallVpGamma = $GAMMA
wallVpMass = $PARTICLE_MASS
EOF
      ;;
    *) echo "[0493b-matrix] ERROR unsupported topology=$topology" >&2; return 2 ;;
  esac
}

write_darcy_0493b() {
  local params=$1
  cat >> "$params" <<'EOF'
darcyBrinkmanEnable = true
darcyChiMode = circle
darcyCircleCx = 0.5
darcyCircleCy = 0.5
darcyCircleR = 0.18
darcyInterfaceWidth = 0.02
darcyAlphaMin = 0.0
darcyAlphaMax = 600.0
darcyQ = 0.1
darcyUSolidX = 0.0
darcyUSolidY = 0.0
darcyBrinkmanForcingMode = mean
darcyCostEvery = 1
darcyCostFilename = darcy_cost_0493b.csv
EOF
}

write_params_0493b() {
  local case_dir=$1 mode=$2 topology=$3 solvent_switch=$4 colloid_switch=$5 darcy=$6
  local params="$case_dir/params/params_0493b.kv"
  mkdir -p "$case_dir/params" "$case_dir/output" "$case_dir/logs"
  cat > "$params" <<EOF
inputState = $STATE
outputDir = $case_dir/output
Lx = 1.0
Ly = 1.0
Nx = $NX
Ny = $NY
dt = $DT
nSteps = $STEPS
bodyAccelerationX = 0.0
bodyAccelerationY = 0.0
keepMeanFlowEnable = false
speciesRegistryEnable = true
speciesCount = 2
species0 = 1 solvent liquid 1.0 1.0 $(awk -v g="$GAMMA" -v m="$SOLVENT_MASS" 'BEGIN{printf "%.17g",g*m}')
species0ResamplingEnable = $solvent_switch
species1 = 2 colloid dispersed 1.0 1.0 $(awk -v g="$GAMMA" -v m="$COLLOID_MASS" 'BEGIN{printf "%.17g",g*m}')
species1ResamplingEnable = $colloid_switch
speciesRequireRegisteredTypes = true
speciesDiagnosticsEnable = false
speciesCellDiagnosticsEnable = false
speciesQ6Enable = $(suite_path_has_q6_0434 "$mode" && echo true || echo false)
speciesQ6Mode = weighted
speciesQ6Sensitivity = 1.0
speciesQ6FallbackMode = common
speciesQ6ComparisonTolerance = 1.0e-11
EOF
  write_topology_0493b "$topology" "$params"
  if [[ "$darcy" == 1 ]]; then
    write_darcy_0493b "$params"
    CUDA_RESAMPLING_CHI_FILTER_ENABLE=true
  else
    CUDA_RESAMPLING_CHI_FILTER_ENABLE=false
  fi
  suite_write_common_params_0434 "$mode" >> "$params"
  printf '%s\n' "$params"
}

run_case_0493b() {
  local name=$1 mode=$2 topology=$3 solvent_switch=$4 colloid_switch=$5 darcy=$6
  local case_dir="$RUN_ROOT/$name"
  local log="$case_dir/logs/run_0493b.log"
  local time_file="$case_dir/logs/time_0493b.txt"
  local params
  params="$(write_params_0493b "$case_dir" "$mode" "$topology" "$solvent_switch" "$colloid_switch" "$darcy")" || return 2

  CUDA_RESAMPLING_CHI_FILTER_ENABLE=false
  [[ "$darcy" == 1 ]] && CUDA_RESAMPLING_CHI_FILTER_ENABLE=true
  suite_export_cuda_flags_0434 "$mode" "$topology"
  export SRC_LIVE_VIS_ENABLE=0 MPCD_LIVE_VIS_ENABLE=0 LIVE_PROGRESS
  suite_preflight_run_ok_0492 "$params" || {
    echo "$name,FAIL,preflight" >> "$RUN_ROOT/status_0493b.csv"; return 0; }

  if [[ "$PREFLIGHT_ONLY" == 1 ]]; then
    echo "$name,PASS,preflight-only" >> "$RUN_ROOT/status_0493b.csv"
    return 0
  fi

  echo "[0493b-matrix] case=$name mode=$mode topology=$topology solvent=$solvent_switch colloid=$colloid_switch darcy=$darcy"
  set +e
  /usr/bin/time -o "$time_file" -f 'elapsed=%e user=%U sys=%S' "$BIN" "$params" > "$log" 2>&1
  local rc=$?
  set -e
  local status=PASS reason=ok
  if [[ $rc -ne 0 ]]; then status=FAIL; reason="rc=$rc"; fi
  if grep -Eqi 'Fatal error|\[.*ERROR|CPU equivalence gate|host patchback|fallback.*CPU' "$log"; then
    status=FAIL; reason=forbidden-log-pattern
  fi
  if grep -Eq 'resampDisabledSpeciesMutationCount,?[^0-9]*[1-9]|disabledSpeciesMutationCount[=:,][[:space:]]*[1-9]' "$log"; then
    status=FAIL; reason=disabled-species-mutation
  fi
  echo "$name,$status,$reason" >> "$RUN_ROOT/status_0493b.csv"
  [[ "$status" == PASS ]] || tail -80 "$log" >&2 || true
}

printf 'case,status,reason\n' > "$RUN_ROOT/status_0493b.csv"
run_case_0493b 01_periodic_all src-resampling periodic true true 0
run_case_0493b 02_periodic_solvent_only src-resampling periodic true false 0
run_case_0493b 03_walls src-resampling wall true true 0
run_case_0493b 04_fullface src-resampling io_fullface true true 0
run_case_0493b 05_segmented src-resampling segmented true true 0
run_case_0493b 06_darcy src-resampling periodic true true 1
run_case_0493b 07_segmented_darcy src-resampling segmented true true 1
run_case_0493b 08_q6_segmented src-q6-resampling segmented true true 0

cat "$RUN_ROOT/status_0493b.csv"
if grep -q ',FAIL,' "$RUN_ROOT/status_0493b.csv"; then
  echo "[0493b-matrix] FAIL" >&2
  exit 2
fi
echo "[0493b-matrix] PASS"
