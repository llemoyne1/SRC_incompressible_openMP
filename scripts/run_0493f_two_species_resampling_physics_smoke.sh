#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434

CASE_LABEL="two_species_resampling_physics_neutral_0493f_fix2"
BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}"
RUN_ROOT="${RUN_ROOT:-runs/0493f_fix2_two_species_neutral_physics}"
NX="${NX:-16}"
NY="${NY:-8}"
GAMMA="${GAMMA:-10}"
SHORT_STEPS="${SHORT_STEPS:-10}"
DT="${DT:-1.0e-7}"
SEED="${SEED:-49307}"
THREADS="${THREADS:-8}"
TARGET_CELL_MASS="${TARGET_CELL_MASS:-10.0}"
SPECIES_TARGET_CELL_MASS="${SPECIES_TARGET_CELL_MASS:-5.0}"
INACTIVE_PARTICLE_MASS="${INACTIVE_PARTICLE_MASS:-1.0}"
TYPE1_UX="${TYPE1_UX:-0.03}"
TYPE1_UY="${TYPE1_UY:--0.01}"
TYPE2_UX="${TYPE2_UX:--0.01}"
TYPE2_UY="${TYPE2_UY:-0.02}"
THERMAL_AMPLITUDE="${THERMAL_AMPLITUDE:-0.01}"
INACTIVE_PER_CELL="${INACTIVE_PER_CELL:-4}"
GUARD_NMIN="${GUARD_NMIN:-$((GAMMA - 1))}"
GUARD_NTARGET="${GUARD_NTARGET:-$GAMMA}"
GUARD_NMAX="${GUARD_NMAX:-$((GAMMA + 1))}"
POOR_MASS_FRACTION="${POOR_MASS_FRACTION:-0.9}"
RICH_MASS_FRACTION="${RICH_MASS_FRACTION:-1.1}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
ANALYZE_ONLY="${ANALYZE_ONLY:-0}"

if (( GAMMA < 4 || GAMMA % 2 != 0 )); then
  echo "[0493f-fix2] ERROR GAMMA must be even and >=4" >&2
  exit 2
fi
if (( (GAMMA - 2) % 2 != 0 || (GAMMA + 2) % 2 != 0 )); then
  echo "[0493f-fix2] ERROR per-species checkerboard counts must be integral" >&2
  exit 2
fi
if (( SHORT_STEPS < 1 )); then
  echo "[0493f-fix2] ERROR SHORT_STEPS must be >=1" >&2
  exit 2
fi
if (( GUARD_NMIN < 1 || GUARD_NMIN > GUARD_NTARGET || GUARD_NTARGET > GUARD_NMAX )); then
  echo "[0493f-fix2] ERROR invalid guard thresholds $GUARD_NMIN/$GUARD_NTARGET/$GUARD_NMAX" >&2
  exit 2
fi
python3 - "$TARGET_CELL_MASS" "$SPECIES_TARGET_CELL_MASS" <<'PY_VALIDATE_MASS'
import math, sys
total, species = map(float, sys.argv[1:])
if not (math.isfinite(total) and math.isfinite(species) and total > 0.0 and species > 0.0):
    raise SystemExit("[0493f-fix2] ERROR target masses must be finite and positive")
if abs(total - 2.0 * species) > 1.0e-12 * max(1.0, abs(total)):
    raise SystemExit("[0493f-fix2] ERROR TARGET_CELL_MASS must equal 2*SPECIES_TARGET_CELL_MASS")
PY_VALIDATE_MASS

export LIVE_PROGRESS OMP_NUM_THREADS="$THREADS"
CASE_LABEL="$CASE_LABEL"
KBT=0.0
U0=0.0
UIN=0.0
SUMMARY_EVERY=1
DUMP_STATE_EVERY=1
DUMP_ROLE_FILTER=all
SUMMARY_ROLE_FILTER=fluid
SPECIES_RESAMPLING_ENABLE=true
SPECIES_RESIDENT_MODE=production
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
CUDA_RESAMPLING_CHI_MIN=0.05
RESAMPLING_EXTRACTION_ENABLE=true
RESAMPLING_INSERTION_ENABLE=true
RESAMPLING_REMAP_ENABLE=true
RESAMPLING_PARTICLE_MASS_MIN=0.1
RESAMPLING_PARTICLE_MASS_MAX=20.0
PROJECTION_BACKEND=cuda
PROJECTION_OPERATOR=auto_fv_cg
PROJECTION_MAX_ITERATIONS=50
PROJECTION_TOLERANCE=1.0e-12
PROJECTION_MOMENTUM_CORRECTION_ENABLE=true
Q6_PROJECTION_STRENGTH=1.0
ROTATION_ANGLE=0.0
RANDOM_ROTATION_SIGN=false
GRID_SHIFT_ENABLE=false
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
if [[ "$PREFLIGHT_ONLY" != 1 && "$ANALYZE_ONLY" != 1 ]]; then suite_ensure_binary_0434; fi

STATE="$RUN_ROOT/init/two_species_neutral_checkerboard_0493f_fix2.smpcd"

make_state_0493f_fix2() {
  local path=$1
  python3 - "$path" "$NX" "$NY" "$GAMMA" "$TARGET_CELL_MASS" "$SPECIES_TARGET_CELL_MASS" \
    "$INACTIVE_PARTICLE_MASS" "$INACTIVE_PER_CELL" \
    "$TYPE1_UX" "$TYPE1_UY" "$TYPE2_UX" "$TYPE2_UY" "$THERMAL_AMPLITUDE" <<'PY_STATE'
import math, os, struct, sys
(path, nx, ny, gamma, target_cell_mass, species_cell_mass,
 inactive_mass, inactive_per_cell,
 t1ux, t1uy, t2ux, t2uy, thermal) = sys.argv[1:]
nx, ny, gamma = int(nx), int(ny), int(gamma)
target_cell_mass, species_cell_mass, inactive_mass = map(float, (target_cell_mass, species_cell_mass, inactive_mass))
inactive_per_cell = int(inactive_per_cell)
t1ux, t1uy, t2ux, t2uy, thermal = map(float, (t1ux, t1uy, t2ux, t2uy, thermal))

x=[]; y=[]; vx=[]; vy=[]; typ=[]; mass=[]; role=[]
poor_particle_mass = None
rich_particle_mass = None
for j in range(ny):
    for i in range(nx):
        n = gamma - 2 if ((i + j) & 1) == 0 else gamma + 2
        nsp = n // 2
        particle_mass = species_cell_mass / nsp
        if n == gamma - 2:
            poor_particle_mass = particle_mass
        else:
            rich_particle_mass = particle_mass
        for k in range(n):
            angle_pos = 2.0 * math.pi * (k + 0.5) / n
            sx = 0.5 + 0.34 * math.cos(angle_pos)
            sy = 0.5 + 0.34 * math.sin(angle_pos)
            t = 1 if (k % 2 == 0) else 2
            local = k // 2
            angle_v = 2.0 * math.pi * (local + 0.5) / nsp
            ux0, uy0 = (t1ux, t1uy) if t == 1 else (t2ux, t2uy)
            x.append((i + sx) / nx)
            y.append((j + sy) / ny)
            vx.append(ux0 + thermal * math.cos(angle_v))
            vy.append(uy0 + thermal * math.sin(angle_v))
            typ.append(t); mass.append(particle_mass); role.append(1)
active = len(x)
inactive = nx * ny * inactive_per_cell
for _ in range(inactive):
    x.append(0.0); y.append(0.0); vx.append(0.0); vy.append(0.0)
    typ.append(0); mass.append(inactive_mass); role.append(0)

os.makedirs(os.path.dirname(path), exist_ok=True)
magic=b"SRCMPCD_STATE" + b"\0"*(16-len("SRCMPCD_STATE"))
reserved=[0]*8; reserved[0]=1; reserved[1]=1
N=len(x)
with open(path,"wb") as f:
    f.write(magic)
    f.write(struct.pack("<IIIIQIIII",2,0x01020304,2,1,N,1,1,8,4))
    f.write(struct.pack("<8Q",*reserved))
    for arr,fmt in [(x,"d"),(y,"d"),(vx,"d"),(vy,"d"),(typ,"I"),(mass,"d"),(role,"B")]:
        f.write(struct.pack(f"<{N}{fmt}",*arr))
print(
    f"[0493f-fix2-state] path={path} grid={nx}x{ny} gamma={gamma} "
    f"fluid={active} inactive={inactive} totalPattern={gamma-2}/{gamma+2} "
    f"perSpeciesPattern={(gamma-2)//2}/{(gamma+2)//2} "
    f"cellMass={target_cell_mass:.17g} speciesCellMass={species_cell_mass:.17g} "
    f"poorParticleMass={poor_particle_mass:.17g} richParticleMass={rich_particle_mass:.17g} types=1,2"
)
PY_STATE
}

write_params_0493f_fix2() {
  local case_dir=$1 mode=$2 steps=$3 type1_switch=$4 type2_switch=$5
  local params="$case_dir/params/params_0493f_fix2.kv"
  mkdir -p "$case_dir/params" "$case_dir/output" "$case_dir/logs"
  cat > "$params" <<EOF_PARAMS
inputState = $STATE
outputDir = $case_dir/output
Lx = 1.0
Ly = 1.0
Nx = $NX
Ny = $NY
dt = $DT
nSteps = $steps
bodyAccelerationX = 0.0
bodyAccelerationY = 0.0
keepMeanFlowEnable = false
speciesRegistryEnable = true
speciesCount = 2
species0 = 1 species_A unspecified 1.0 1.0 $SPECIES_TARGET_CELL_MASS
species1 = 2 species_B unspecified 1.0 1.0 $SPECIES_TARGET_CELL_MASS
species0ResamplingEnable = $type1_switch
species1ResamplingEnable = $type2_switch
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
EOF_PARAMS
  suite_write_common_params_0434 "$mode" >> "$params"
  cat >> "$params" <<EOF_PARAMS
# 0493f-fix2: population checkerboard with physically uniform total/species mass fields.
resamplingTargetCellMass = $TARGET_CELL_MASS
resamplingPoorCellMassFraction = $POOR_MASS_FRACTION
resamplingRichCellMassFraction = $RICH_MASS_FRACTION
EOF_PARAMS
  printf '%s\n' "$params"
}

run_case_0493f_fix2() {
  local name=$1 mode=$2 steps=$3 type1_switch=$4 type2_switch=$5
  local case_dir="$RUN_ROOT/$name"
  local params log time_file
  params="$(write_params_0493f_fix2 "$case_dir" "$mode" "$steps" "$type1_switch" "$type2_switch")"
  log="$case_dir/logs/run_0493f_fix2.log"
  time_file="$case_dir/logs/time_0493f_fix2.txt"
  suite_export_cuda_flags_0434 "$mode" periodic
  export SRC_LIVE_VIS_ENABLE=0 MPCD_LIVE_VIS_ENABLE=0 LIVE_PROGRESS
  if ! suite_preflight_run_ok_0492 "$params"; then
    echo "$name,FAIL,preflight" >> "$RUN_ROOT/status_0493f_fix2.csv"
    return 0
  fi
  if [[ "$PREFLIGHT_ONLY" == 1 ]]; then
    echo "$name,PASS,preflight-only" >> "$RUN_ROOT/status_0493f_fix2.csv"
    return 0
  fi
  echo "[0493f-fix2] case=$name mode=$mode steps=$steps type1=$type1_switch type2=$type2_switch"
  set +e
  /usr/bin/time -o "$time_file" -f 'elapsed=%e user=%U sys=%S' "$BIN" "$params" > "$log" 2>&1
  local rc=$?
  set -e
  local status=PASS reason=ok
  if [[ $rc -ne 0 ]]; then status=FAIL; reason="rc=$rc"; fi
  if grep -Eqi 'Fatal error|\[.*ERROR|CPU equivalence gate|host patchback|fallback.*CPU' "$log"; then
    status=FAIL; reason=forbidden-log-pattern
  fi
  echo "$name,$status,$reason" >> "$RUN_ROOT/status_0493f_fix2.csv"
  [[ "$status" == PASS ]] || tail -100 "$log" >&2 || true
}

if [[ "$ANALYZE_ONLY" != 1 ]]; then
  make_state_0493f_fix2 "$STATE"
  printf 'case,status,reason\n' > "$RUN_ROOT/status_0493f_fix2.csv"
  run_case_0493f_fix2 00_no_resampling src "$SHORT_STEPS" false false
  run_case_0493f_fix2 01_both_species src-resampling "$SHORT_STEPS" true true
  run_case_0493f_fix2 02_type1_only src-resampling "$SHORT_STEPS" true false
  run_case_0493f_fix2 03_type2_only src-resampling "$SHORT_STEPS" false true
  run_case_0493f_fix2 04_no_species_enabled src-resampling "$SHORT_STEPS" false false
  cat "$RUN_ROOT/status_0493f_fix2.csv"
  if grep -q ',FAIL,' "$RUN_ROOT/status_0493f_fix2.csv"; then
    echo "[0493f-fix2] FAIL runner" >&2
    exit 2
  fi
  if [[ "$PREFLIGHT_ONLY" == 1 ]]; then
    echo "[0493f-fix2] PASS preflight"
    exit 0
  fi
fi

python3 scripts/analyze_0493f_two_species_resampling_physics.py \
  --root "$RUN_ROOT" --nx "$NX" --ny "$NY" --gamma "$GAMMA" \
  --target-cell-mass "$TARGET_CELL_MASS" \
  --species-target-cell-mass "$SPECIES_TARGET_CELL_MASS" \
  --short-step "$SHORT_STEPS"
