#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434

CASE_LABEL="periodic_shear_wave_physics_0493h"
BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}"
RUN_ROOT="${RUN_ROOT:-runs/0493h_periodic_shear_wave_physics}"
NX="${NX:-32}"
NY="${NY:-32}"
GAMMA="${GAMMA:-20}"
STEPS="${STEPS:-300}"
DT="${DT:-0.002}"
DUMP_EVERY="${DUMP_EVERY:-10}"
SEEDS="${SEEDS:-493081 493082}"
SEED="${SEED:-493081}"
THREADS="${THREADS:-8}"
WAVE_MODE="${WAVE_MODE:-1}"
WAVE_AMPLITUDE="${WAVE_AMPLITUDE:-0.08}"
MEAN_UX="${MEAN_UX:-0.0}"
MEAN_UY="${MEAN_UY:-0.0}"
THERMAL_AMPLITUDE="${THERMAL_AMPLITUDE:-0.04}"
PARTICLE_MASS="${PARTICLE_MASS:-1.0}"
INACTIVE_PER_CELL="${INACTIVE_PER_CELL:-8}"
GUARD_NMIN="${GUARD_NMIN:-$((GAMMA - 2))}"
GUARD_NTARGET="${GUARD_NTARGET:-$GAMMA}"
GUARD_NMAX="${GUARD_NMAX:-$((GAMMA + 2))}"
POOR_MASS_FRACTION="${POOR_MASS_FRACTION:-0.9}"
RICH_MASS_FRACTION="${RICH_MASS_FRACTION:-1.1}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
ANALYZE_ONLY="${ANALYZE_ONLY:-0}"

if (( NX < 8 || NY < 8 || GAMMA < 4 || GAMMA % 2 != 0 )); then
  echo "[0493h] ERROR NX/NY must be >=8 and GAMMA must be even and >=4" >&2
  exit 2
fi
if (( STEPS < DUMP_EVERY || DUMP_EVERY < 1 || STEPS % DUMP_EVERY != 0 )); then
  echo "[0493h] ERROR require STEPS>=DUMP_EVERY>=1 and STEPS divisible by DUMP_EVERY" >&2
  exit 2
fi
if (( WAVE_MODE < 1 || INACTIVE_PER_CELL < 2 )); then
  echo "[0493h] ERROR WAVE_MODE>=1 and INACTIVE_PER_CELL>=2 required" >&2
  exit 2
fi
python3 - "$DT" "$WAVE_AMPLITUDE" "$THERMAL_AMPLITUDE" "$PARTICLE_MASS" <<'PY_VALIDATE'
import math, sys
vals=list(map(float,sys.argv[1:]))
if not all(math.isfinite(x) for x in vals): raise SystemExit('[0493h] ERROR non-finite physical parameter')
if vals[0] <= 0 or vals[1] <= 0 or vals[2] < 0 or vals[3] <= 0:
    raise SystemExit('[0493h] ERROR require DT>0, WAVE_AMPLITUDE>0, THERMAL_AMPLITUDE>=0, PARTICLE_MASS>0')
PY_VALIDATE

export LIVE_PROGRESS OMP_NUM_THREADS="$THREADS"
CASE_LABEL="$CASE_LABEL"
KBT=0.0
U0=0.0
UIN=0.0
SUMMARY_EVERY="$DUMP_EVERY"
DUMP_STATE_EVERY="$DUMP_EVERY"
DUMP_ROLE_FILTER=fluid
SUMMARY_ROLE_FILTER=fluid
SPECIES_RESAMPLING_ENABLE=true
SPECIES_RESIDENT_MODE="${SPECIES_RESIDENT_MODE:-production}"
SPECIES_VALIDATION_MATERIALIZE_EVERY=1
RESAMPLING_PRODUCTION_STRIP=1
RESAMPLING_DIAG_CSV_ENABLE=0
RESAMPLING_FULL_GATE_ENABLE=0
RESAMPLING_REMAP_CELL_COUNT_DIAG_ENABLE=0
RESAMPLING_UPSTREAM_VALIDATE_ENABLE=0
RESAMPLING_OPERATION_MATERIALIZER_VALIDATE_ENABLE=0
RESAMPLING_HOST_PATCHBACK_ENABLE=0
RESAMPLING_SPARSE_DEVICE_GATE_ENABLE=0
RESAMPLING_THERMAL_RENORMALIZATION_ENABLE=false
RESAMPLING_MASS_GUARD_ENABLE=false
MASS_RECONDITION_ENABLE=0
GUARD_EVERY=1
RESTORE_ENABLE=1
RESAMPLING_SURVEY_ENABLE=0
RESAMPLING_ADAPTIVE_FLAG_ENABLE=0
FLAG_EVERY=1000000
CUDA_RESAMPLING_CHI_FILTER_ENABLE=false
RESAMPLING_EXTRACTION_ENABLE=true
RESAMPLING_INSERTION_ENABLE=true
RESAMPLING_REMAP_ENABLE=true
RESAMPLING_PARTICLE_MASS_MIN=0.05
RESAMPLING_PARTICLE_MASS_MAX=20.0
PROJECTION_BACKEND=cuda
PROJECTION_OPERATOR=auto_fv_cg
PROJECTION_MAX_ITERATIONS=50
PROJECTION_TOLERANCE=1.0e-12
PROJECTION_MOMENTUM_CORRECTION_ENABLE=true
Q6_PROJECTION_STRENGTH=1.0
ROTATION_ANGLE=2.0943951023931953
RANDOM_ROTATION_SIGN=true
GRID_SHIFT_ENABLE=true
THERMOSTAT_ENABLE=false
THERMOSTAT_MODE=cell_relative_rescale
THERMOSTAT_EVERY=1
THERMOSTAT_TARGET_KBT=0.0
THERMOSTAT_MIN_PARTICLES=2
LIVE_VIS_ENABLE=0
FILTERED_RECORDING_ENABLE=0
RECORD_ENABLE=false
PARTICLE_TYPE_FILTER=-1

suite_defaults_common_0434
suite_compute_derived_0434

if [[ "$ANALYZE_ONLY" != 1 ]]; then
  if [[ "$CLEAN_RUN_ROOT" == 1 ]]; then rm -rf "$RUN_ROOT"; fi
  mkdir -p "$RUN_ROOT/init" "$RUN_ROOT/logs"
fi
if [[ "$PREFLIGHT_ONLY" != 1 && "$ANALYZE_ONLY" != 1 ]]; then
  suite_ensure_binary_0434
  if [[ "$BIN" -ot src/cuda_species_mass_closure_0490i.cu ||
        "$BIN" -ot src/cuda_species_cell_fields_0490h.cu ]]; then
    echo "[0493h] ERROR binary is older than the 0493j kinetic-closure sources; rebuild first" >&2
    echo "[0493h] build command: bash scripts/build_src_mpcd_cuda_q6_resident_livevis_0486.sh" >&2
    exit 2
  fi
fi

STATE="$RUN_ROOT/init/periodic_shear_wave_0493h.smpcd"
TARGET_CELL_MASS="$(python3 - "$GAMMA" "$PARTICLE_MASS" <<'PY_MASS'
import sys
print(int(sys.argv[1])*float(sys.argv[2]))
PY_MASS
)"

make_state_0493h() {
  local path=$1
  python3 - "$path" "$NX" "$NY" "$GAMMA" "$WAVE_MODE" "$WAVE_AMPLITUDE" \
    "$MEAN_UX" "$MEAN_UY" "$THERMAL_AMPLITUDE" "$PARTICLE_MASS" "$INACTIVE_PER_CELL" <<'PY_STATE'
import math, os, struct, sys
(path,nx,ny,gamma,mode,amp,mean_ux,mean_uy,thermal,particle_mass,inactive_per_cell)=sys.argv[1:]
nx,ny,gamma,mode,inactive_per_cell=map(int,(nx,ny,gamma,mode,inactive_per_cell))
amp,mean_ux,mean_uy,thermal,particle_mass=map(float,(amp,mean_ux,mean_uy,thermal,particle_mass))

x=[]; y=[]; vx=[]; vy=[]; typ=[]; mass=[]; role=[]
pairs=gamma//2
for j in range(ny):
    for i in range(nx):
        for p in range(pairs):
            fy=(p+0.5)/pairs
            gy=(j+fy)/ny
            wave=amp*math.sin(2.0*math.pi*mode*gy)
            theta=2.0*math.pi*(p+0.5)/pairs
            tx=thermal*math.cos(theta); ty=thermal*math.sin(theta)
            # Pair particles at the same y, with opposite thermal velocities.
            for sign,fx in ((1.0,0.25),(-1.0,0.75)):
                x.append((i+fx)/nx); y.append(gy)
                vx.append(mean_ux+wave+sign*tx); vy.append(mean_uy+sign*ty)
                typ.append(1); mass.append(particle_mass); role.append(1)
active=len(x)
inactive=nx*ny*inactive_per_cell
for _ in range(inactive):
    x.append(0.0); y.append(0.0); vx.append(0.0); vy.append(0.0)
    typ.append(0); mass.append(particle_mass); role.append(0)

os.makedirs(os.path.dirname(path),exist_ok=True)
magic=b'SRCMPCD_STATE'+b'\0'*(16-len('SRCMPCD_STATE'))
reserved=[0]*8; reserved[0]=1; reserved[1]=1
N=len(x)
with open(path,'wb') as f:
    f.write(magic)
    f.write(struct.pack('<IIIIQIIII',2,0x01020304,2,1,N,1,1,8,4))
    f.write(struct.pack('<8Q',*reserved))
    for arr,fmt in ((x,'d'),(y,'d'),(vx,'d'),(vy,'d'),(typ,'I'),(mass,'d'),(role,'B')):
        f.write(struct.pack(f'<{N}{fmt}',*arr))
M=sum(mass[:active]); px=sum(m*v for m,v in zip(mass[:active],vx[:active])); py=sum(m*v for m,v in zip(mass[:active],vy[:active]))
print(f'[0493h-state] path={path} grid={nx}x{ny} gamma={gamma} fluid={active} inactive={inactive} mode={mode} amplitude={amp:.17g} thermal={thermal:.17g} mass={M:.17g} px={px:.3e} py={py:.3e}')
PY_STATE
}

write_params_0493h() {
  local case_dir=$1 mode=$2 seed=$3 switch=$4
  local params="$case_dir/params/params_0493h.kv"
  mkdir -p "$case_dir/params" "$case_dir/output" "$case_dir/logs"
  cat > "$params" <<EOF_PARAMS
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
speciesCount = 1
species0 = 1 shear_fluid unspecified 1.0 1.0 $TARGET_CELL_MASS
species0ResamplingEnable = $switch
speciesRequireRegisteredTypes = true
speciesDiagnosticsEnable = false
speciesCellDiagnosticsEnable = false
speciesQ6Enable = false
speciesQ6Mode = weighted
speciesQ6Sensitivity = 1.0
speciesQ6FallbackMode = common
speciesQ6ComparisonTolerance = 1.0e-11
speciesMassClosureCudaDiagnosticsFilename = cuda_species_mass_closure_0490i.csv
speciesTransferCudaDiagnosticsFilename = cuda_species_transfer_plan_0490k.csv
speciesCudaResidentFastPathDiagnosticsFilename = cuda_species_resident_fast_path_0490m.csv
speciesCudaResidentMaintenanceDiagnosticsFilename = cuda_species_resident_maintenance_0490n.csv
bcLeft = periodic
bcRight = periodic
bcBottom = periodic
bcTop = periodic
bcX = periodic
bcY = periodic
rngSeed = $seed
EOF_PARAMS
  suite_write_common_params_0434 "$mode" >> "$params"
  cat >> "$params" <<EOF_PARAMS
# 0493h: periodic shear-wave decay; no Q6, Darcy, walls, forcing or thermostat.
resamplingTargetCellMass = $TARGET_CELL_MASS
resamplingPoorCellMassFraction = $POOR_MASS_FRACTION
resamplingRichCellMassFraction = $RICH_MASS_FRACTION
EOF_PARAMS
  printf '%s\n' "$params"
}

run_case_0493h() {
  local seed=$1 name=$2 mode=$3 switch=$4
  SEED="$seed"
  local case_dir="$RUN_ROOT/seed_${seed}/$name"
  local params log time_file
  params="$(write_params_0493h "$case_dir" "$mode" "$seed" "$switch")"
  log="$case_dir/logs/run_0493h.log"
  time_file="$case_dir/logs/time_0493h.txt"
  suite_export_cuda_flags_0434 "$mode" periodic
  export SRC_LIVE_VIS_ENABLE=0 MPCD_LIVE_VIS_ENABLE=0 LIVE_PROGRESS
  if ! suite_preflight_run_ok_0492 "$params"; then
    echo "$seed,$name,FAIL,preflight" >> "$RUN_ROOT/status_0493h.csv"
    return 0
  fi
  if [[ "$PREFLIGHT_ONLY" == 1 ]]; then
    echo "$seed,$name,PASS,preflight-only" >> "$RUN_ROOT/status_0493h.csv"
    return 0
  fi
  echo "[0493h] seed=$seed case=$name mode=$mode steps=$STEPS amplitude=$WAVE_AMPLITUDE"
  set +e
  /usr/bin/time -o "$time_file" -f 'elapsed=%e user=%U sys=%S' "$BIN" "$params" > "$log" 2>&1
  local rc=$?
  set -e
  local status=PASS reason=ok
  if [[ $rc -ne 0 ]]; then status=FAIL; reason="rc=$rc"; fi
  if grep -Eqi 'Fatal error|\[.*ERROR|CPU equivalence gate|host patchback|fallback.*CPU' "$log"; then
    status=FAIL; reason=forbidden-log-pattern
  fi
  echo "$seed,$name,$status,$reason" >> "$RUN_ROOT/status_0493h.csv"
  [[ "$status" == PASS ]] || tail -120 "$log" >&2 || true
}

if [[ "$ANALYZE_ONLY" != 1 ]]; then
  make_state_0493h "$STATE"
  printf 'seed,case,status,reason\n' > "$RUN_ROOT/status_0493h.csv"
  for seed in $SEEDS; do
    run_case_0493h "$seed" 00_src src false
    run_case_0493h "$seed" 01_src_resampling src-resampling true
  done
  cat "$RUN_ROOT/status_0493h.csv"
  if grep -q ',FAIL,' "$RUN_ROOT/status_0493h.csv"; then
    echo "[0493h] FAIL runner" >&2
    exit 2
  fi
  if [[ "$PREFLIGHT_ONLY" == 1 ]]; then
    echo "[0493h] PASS preflight"
    exit 0
  fi
fi

python3 scripts/analyze_0493h_periodic_shear_wave_physics.py \
  --root "$RUN_ROOT" --nx "$NX" --ny "$NY" --gamma "$GAMMA" \
  --dt "$DT" --steps "$STEPS" --dump-every "$DUMP_EVERY" \
  --wave-mode "$WAVE_MODE" --requested-amplitude "$WAVE_AMPLITUDE" \
  --thermal-amplitude "$THERMAL_AMPLITUDE" --seeds $SEEDS
