#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434

CASE_LABEL="monospecies_resampling_physics_0493e"
BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}"
RUN_ROOT="${RUN_ROOT:-runs/0493e_monospecies_resampling_physics}"
NX="${NX:-16}"
NY="${NY:-8}"
GAMMA="${GAMMA:-10}"
SHORT_STEPS="${SHORT_STEPS:-10}"
DT="${DT:-1.0e-7}"
SEED="${SEED:-49305}"
THREADS="${THREADS:-8}"
PARTICLE_MASS="${PARTICLE_MASS:-1.0}"
MEAN_UX="${MEAN_UX:-0.02}"
MEAN_UY="${MEAN_UY:--0.01}"
THERMAL_AMPLITUDE="${THERMAL_AMPLITUDE:-0.01}"
INACTIVE_PER_CELL="${INACTIVE_PER_CELL:-4}"
GUARD_NMIN="${GUARD_NMIN:-$((GAMMA - 1))}"
GUARD_NTARGET="${GUARD_NTARGET:-$GAMMA}"
GUARD_NMAX="${GUARD_NMAX:-$((GAMMA + 1))}"
TARGET_CELL_MASS="${TARGET_CELL_MASS:-$(awk -v g="$GAMMA" -v m="$PARTICLE_MASS" 'BEGIN{printf "%.17g",g*m}')}"
POOR_MASS_FRACTION="${POOR_MASS_FRACTION:-0.9}"
RICH_MASS_FRACTION="${RICH_MASS_FRACTION:-1.1}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
ANALYZE_ONLY="${ANALYZE_ONLY:-0}"

if (( GAMMA < 4 || GAMMA % 2 != 0 )); then
  echo "[0493e] ERROR GAMMA must be even and >=4" >&2
  exit 2
fi
if (( SHORT_STEPS < 1 )); then
  echo "[0493e] ERROR SHORT_STEPS must be >=1" >&2
  exit 2
fi
if (( GUARD_NMIN < 1 || GUARD_NMIN > GUARD_NTARGET || GUARD_NTARGET > GUARD_NMAX )); then
  echo "[0493e] ERROR invalid guard thresholds $GUARD_NMIN/$GUARD_NTARGET/$GUARD_NMAX" >&2
  exit 2
fi

export LIVE_PROGRESS OMP_NUM_THREADS="$THREADS"
CASE_LABEL="$CASE_LABEL"
KBT=0.0
U0="$MEAN_UX"
UIN="$MEAN_UX"
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

STATE="$RUN_ROOT/init/mono_checkerboard_0493e.smpcd"

make_state_0493e() {
  local path=$1
  python3 - "$path" "$NX" "$NY" "$GAMMA" "$PARTICLE_MASS" "$INACTIVE_PER_CELL" "$MEAN_UX" "$MEAN_UY" "$THERMAL_AMPLITUDE" <<'PY_STATE'
import math, os, struct, sys
path, nx, ny, gamma, mass0, inactive_per_cell, ux0, uy0, thermal = sys.argv[1:]
nx, ny, gamma = int(nx), int(ny), int(gamma)
mass0, ux0, uy0, thermal = map(float, (mass0, ux0, uy0, thermal))
inactive_per_cell = int(inactive_per_cell)

x=[]; y=[]; vx=[]; vy=[]; typ=[]; mass=[]; role=[]
for j in range(ny):
    for i in range(nx):
        n = gamma - 2 if ((i + j) & 1) == 0 else gamma + 2
        positions = [
            (0.5 + 0.34 * math.cos(2.0 * math.pi * (k + 0.5) / n),
             0.5 + 0.34 * math.sin(2.0 * math.pi * (k + 0.5) / n))
            for k in range(n)
        ]
        for k, (sx, sy) in enumerate(positions):
            x.append((i + sx) / nx)
            y.append((j + sy) / ny)
            pair = k // 2
            angle = 2.0 * math.pi * (pair + 0.5) / max(1, n // 2)
            sign = 1.0 if (k % 2 == 0) else -1.0
            vx.append(ux0 + sign * thermal * math.cos(angle))
            vy.append(uy0 + sign * thermal * math.sin(angle))
            typ.append(1)
            mass.append(mass0)
            role.append(1)
active = len(x)
inactive = nx * ny * inactive_per_cell
for _ in range(inactive):
    x.append(0.0); y.append(0.0); vx.append(0.0); vy.append(0.0)
    typ.append(0); mass.append(mass0); role.append(0)

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
print(f"[0493e-state] path={path} grid={nx}x{ny} gamma={gamma} fluid={active} inactive={inactive} pattern={gamma-2}/{gamma+2} type=1")
PY_STATE
}

write_params_0493e() {
  local case_dir=$1 mode=$2 steps=$3 resampling_switch=$4
  local params="$case_dir/params/params_0493e.kv"
  mkdir -p "$case_dir/params" "$case_dir/output" "$case_dir/logs"
  cat > "$params" <<EOF
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
speciesCount = 1
species0 = 1 mono liquid 1.0 1.0 $TARGET_CELL_MASS
species0ResamplingEnable = $resampling_switch
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
EOF
  suite_write_common_params_0434 "$mode" >> "$params"
  cat >> "$params" <<EOF
# 0493e: explicit mono-species physical target.
resamplingTargetCellMass = $TARGET_CELL_MASS
resamplingPoorCellMassFraction = $POOR_MASS_FRACTION
resamplingRichCellMassFraction = $RICH_MASS_FRACTION
EOF
  printf '%s\n' "$params"
}

run_case_0493e() {
  local name=$1 mode=$2 steps=$3 resampling_switch=$4
  local case_dir="$RUN_ROOT/$name"
  local params log time_file
  params="$(write_params_0493e "$case_dir" "$mode" "$steps" "$resampling_switch")"
  log="$case_dir/logs/run_0493e.log"
  time_file="$case_dir/logs/time_0493e.txt"
  suite_export_cuda_flags_0434 "$mode" periodic
  export SRC_LIVE_VIS_ENABLE=0 MPCD_LIVE_VIS_ENABLE=0 LIVE_PROGRESS
  if ! suite_preflight_run_ok_0492 "$params"; then
    echo "$name,FAIL,preflight" >> "$RUN_ROOT/status_0493e.csv"
    return 0
  fi
  if [[ "$PREFLIGHT_ONLY" == 1 ]]; then
    echo "$name,PASS,preflight-only" >> "$RUN_ROOT/status_0493e.csv"
    return 0
  fi
  echo "[0493e] case=$name mode=$mode steps=$steps monoSpecies=1 resampling=$resampling_switch"
  set +e
  /usr/bin/time -o "$time_file" -f 'elapsed=%e user=%U sys=%S' "$BIN" "$params" > "$log" 2>&1
  local rc=$?
  set -e
  local status=PASS reason=ok
  if [[ $rc -ne 0 ]]; then status=FAIL; reason="rc=$rc"; fi
  if grep -Eqi 'Fatal error|\[.*ERROR|CPU equivalence gate|host patchback|fallback.*CPU' "$log"; then
    status=FAIL; reason=forbidden-log-pattern
  fi
  echo "$name,$status,$reason" >> "$RUN_ROOT/status_0493e.csv"
  [[ "$status" == PASS ]] || tail -100 "$log" >&2 || true
}

if [[ "$ANALYZE_ONLY" != 1 ]]; then
  make_state_0493e "$STATE"
  printf 'case,status,reason\n' > "$RUN_ROOT/status_0493e.csv"
  run_case_0493e 00_no_resampling src 1 false
  run_case_0493e 01_resampling_on src-resampling "$SHORT_STEPS" true
  cat "$RUN_ROOT/status_0493e.csv"
  if grep -q ',FAIL,' "$RUN_ROOT/status_0493e.csv"; then
    echo "[0493e] FAIL runner" >&2
    exit 2
  fi
  if [[ "$PREFLIGHT_ONLY" == 1 ]]; then
    echo "[0493e] PASS preflight"
    exit 0
  fi
fi

python3 scripts/analyze_0493e_monospecies_resampling_physics.py \
  --root "$RUN_ROOT" --nx "$NX" --ny "$NY" --gamma "$GAMMA" \
  --mass "$PARTICLE_MASS" --short-step "$SHORT_STEPS"

echo "[0493e] PASS"
