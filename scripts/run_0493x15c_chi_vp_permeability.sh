#!/usr/bin/env bash

# 0493x15c — fixed chi Brinkman slab + chiVP permeability qualification.
# Third dependent step of the chi-solid audit.
# Physics is unchanged from x15b.  In addition to the exact force budget, the
# streaming diagnostic measures signed and gross particle-mass crossings of the
# mid-plane of the fixed vertical chi slab.  No new user-facing physics or
# diagnostic parameter is introduced.

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
source "$ROOT/scripts/src_mpcd_run_common_0434.sh"
suite_root_cd_0434 || exit $?

CASE_LABEL="0493x15c_chi_vp_permeability"
MODE="src"
TOPOLOGY="periodic"
GEN_CASE="uniform"

Lx="${Lx:-0.5}"
Ly="${Ly:-0.25}"
NX="${NX:-128}"
NY="${NY:-64}"
GAMMA="${GAMMA:-20}"
STEPS="${STEPS:-5000}"
DT="${DT:-0.002}"
KBT="${KBT:-0.125}"
SEED="${SEED:-4931501}"
PARTICLE_MASS="${PARTICLE_MASS:-1.0}"
U0=0.0
VELOCITY_MODE=zero
BACKGROUND_TYPE=0
INACTIVE_TYPE=0
INACTIVE_SLOTS=0
SKIP_SOLID_CELLS=false
SKIP_SOLID_PARTICLES=false

SLAB_CELLS="${SLAB_CELLS:-8}"
ALPHA="${ALPHA:-10.0}"
ALPHA_MIN=0.0
DARCY_Q="${DARCY_Q:-0.1}"
DARCY_USOLID_X=0.0
DARCY_USOLID_Y=0.0
DARCY_BRINKMAN_FORCING_MODE=mean
DARCY_INITIAL_DEACTIVATE_BELOW_CHI=-1.0
DARCY_CHI_COLLISION_VP_ENABLE=true
DARCY_CHI_COLLISION_VP_MODE=interface_band
DARCY_CHI_COLLISION_VP_GAMMA="$GAMMA"
DARCY_CHI_COLLISION_VP_MASS="$PARTICLE_MASS"
DARCY_CHI_COLLISION_VP_LAYERS="${DARCY_CHI_COLLISION_VP_LAYERS:-1}"
DARCY_CHI_COLLISION_VP_THRESHOLD="${DARCY_CHI_COLLISION_VP_THRESHOLD:-0.5}"
DARCY_CHI_COLLISION_VP_STRENGTH="${DARCY_CHI_COLLISION_VP_STRENGTH:-0.25}"
BODY_AX="${BODY_AX:-0.006305394872053156}"

ROTATION_ANGLE="${ROTATION_ANGLE:-1.5707963267948966}"
RANDOM_ROTATION_SIGN=true
GRID_SHIFT_ENABLE=true
THERMOSTAT_ENABLE=true
THERMOSTAT_MODE=cell_relative_rescale
THERMOSTAT_EVERY=1
THERMOSTAT_TARGET_KBT="$KBT"
THERMOSTAT_MIN_PARTICLES=3
WEIGHTED_RESAMPLING_ENABLE_OVERRIDE=false
CUDA_EMPTY_REFILL_ENABLE_OVERRIDE=false
SPECIES_RESAMPLING_ENABLE=false

SUMMARY_EVERY=1
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-1000}"
DARCY_COST_EVERY=1
TOPO_BENCHMARK_ENABLE=true
TOPO_BENCHMARK_EVERY=1
TOPO_BENCHMARK_FILENAME=topo_benchmark_0493x15c.csv
TOPO_BENCHMARK_FORCE_ENABLE=true
TOPO_BENCHMARK_DRAG_LIFT_ENABLE=false

LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-ux}"
LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-1}"
LIVE_VIS_NX="${LIVE_VIS_NX:-96}"
LIVE_VIS_NY="${LIVE_VIS_NY:-48}"
LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-0}"
FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-1}"
RECORD_ENABLE="${RECORD_ENABLE:-true}"
RECORD_FIELDS="${RECORD_FIELDS:-rho,ux,uy}"
RECORD_EVERY="${RECORD_EVERY:-100}"
FILTER_MODE="${FILTER_MODE:-none}"
FILTER_SAMPLE_EVERY="${FILTER_SAMPLE_EVERY:-100}"
PARTICLE_TYPE_FILTER="${PARTICLE_TYPE_FILTER:--1}"

RESTART="${RESTART:-0}"
RESTART_STATE="${RESTART_STATE:-}"
RESTART_TAG="${RESTART_TAG:-restart}"
BASE_RUN_ROOT="${BASE_RUN_ROOT:-runs/0493x15c_chi_vp_permeability}"
CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"
PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"

suite_defaults_common_0434
suite_compute_derived_0434
suite_validate_path_0434 "$MODE" || exit $?

if (( NX < 32 || NY < 16 || SLAB_CELLS < 1 || SLAB_CELLS >= NX/2 )); then
  echo "[0493x15c] ERROR require NX>=32 NY>=16 and 1<=SLAB_CELLS<NX/2" >&2
  exit 2
fi

if suite_truthy_0434 "$RESTART"; then
  if [[ -z "$RESTART_STATE" || ! -s "$RESTART_STATE" ]]; then
    echo "[0493x15c] ERROR RESTART=1 requires RESTART_STATE=/path/state_step_N.smpcd" >&2
    exit 2
  fi
  RUN_ROOT="$BASE_RUN_ROOT/$RESTART_TAG"
  INPUT_STATE="$RESTART_STATE"
else
  RUN_ROOT="$BASE_RUN_ROOT/fresh"
  if suite_truthy_0434 "$CLEAN_RUN_ROOT"; then rm -rf "$RUN_ROOT"; fi
fi

suite_prepare_dirs_0434 "$RUN_ROOT"
STATE="$RUN_ROOT/init/${CASE_LABEL}_${NX}x${NY}_g${GAMMA}.smpcd"
CHI="$RUN_ROOT/chi/${CASE_LABEL}_chi_f32.f32"
PARAMS="$RUN_ROOT/params/${CASE_LABEL}.kv"
OUT="$RUN_ROOT/output"
LOG="$RUN_ROOT/logs/${CASE_LABEL}.log"
TIMEFILE="$RUN_ROOT/logs/${CASE_LABEL}.time"
LIVE_VIS_CONTROL_FILE="$RUN_ROOT/params/${CASE_LABEL}_livevis_control.kv"
mkdir -p "$OUT"

if ! suite_truthy_0434 "$RESTART"; then
  suite_generate_case_0434 "$STATE" "" || exit $?
  INPUT_STATE="$STATE"
fi

python3 - "$CHI" "$NX" "$NY" "$SLAB_CELLS" <<'PY_X15C_CHI'
import struct, sys
from pathlib import Path
path=Path(sys.argv[1]); nx=int(sys.argv[2]); ny=int(sys.argv[3]); w=int(sys.argv[4])
mid=nx//2
lo=mid-w//2
hi=lo+w
vals=[]
for j in range(ny):
    for i in range(nx):
        vals.append(0.0 if lo <= i < hi else 1.0)
path.parent.mkdir(parents=True, exist_ok=True)
path.write_bytes(struct.pack(f"<{len(vals)}f", *vals))
print(f"[0493x15c] chi={path} vertical_slab_cells=[{lo},{hi}) width={w}/{nx}")
PY_X15C_CHI

cat > "$PARAMS" <<PARAMS
inputState = $INPUT_STATE
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
bodyAccelerationX = $BODY_AX
bodyAccelerationY = 0.0
taylorGreenForcingEnable = false
wallAccommodation = 0.0
wallVpEnable = false
PARAMS
suite_write_common_params_0434 "$MODE" >> "$PARAMS"
suite_write_darcy_params_0434 "$CHI" "$MODE" >> "$PARAMS"

# 0493x15c: one run-local LiveVis control remains the single source
# of truth for both interactive display and filtered recording.  No recorder-
# specific bypass/flag is used and ./livevis_control.kv is left untouched.
cat > "$LIVE_VIS_CONTROL_FILE" <<LIVEVIS_CONTROL_KV
recordEnable = ${RECORD_ENABLE}
recordSession = ${CASE_LABEL}_${MODE}
recordFields = ${RECORD_FIELDS}
recordFormat = ${RECORD_FORMAT}
recordEvery = ${RECORD_EVERY}
liveGridNx = ${LIVE_VIS_NX}
liveGridNy = ${LIVE_VIS_NY}
field = ${LIVE_VIS_FIELD}
filterMode = ${FILTER_MODE}
filterSampleEvery = ${FILTER_SAMPLE_EVERY}
smoothPasses = 0
particleTypeFilter = ${PARTICLE_TYPE_FILTER}
LIVEVIS_CONTROL_KV

suite_export_cuda_flags_0434 "$MODE" "$TOPOLOGY"
export MPCD_CHI_SOLID_IMPULSE_DIAG_0493X15A=1
export MPCD_DARCY_EXACT_MOMENTUM_DIAG_0493X8A=1
suite_export_livevis_0434
suite_write_env_file_0434 "$RUN_ROOT/logs/environment_0493x15c.env" "$MODE"

cat > "$RUN_ROOT/run_meta_0493x15c.txt" <<META
case=$CASE_LABEL
mode=$MODE
topology=$TOPOLOGY
Lx=$Lx
Ly=$Ly
Nx=$NX
Ny=$NY
gamma=$GAMMA
dt=$DT
steps=$STEPS
bodyAccelerationX=$BODY_AX
alpha=$ALPHA
slabCells=$SLAB_CELLS
darcyMode=$DARCY_BRINKMAN_FORCING_MODE
chiVp=$DARCY_CHI_COLLISION_VP_ENABLE
chiVpLayers=$DARCY_CHI_COLLISION_VP_LAYERS
chiVpThreshold=$DARCY_CHI_COLLISION_VP_THRESHOLD
chiVpStrength=$DARCY_CHI_COLLISION_VP_STRENGTH
restart=$RESTART
inputState=$INPUT_STATE
livevisControl=$LIVE_VIS_CONTROL_FILE
liveEvery=$LIVE_VIS_EVERY
recordEvery=$RECORD_EVERY
dumpEvery=$DUMP_STATE_EVERY
META

printf '\n===== 0493x15c CHI-VP PERMEABILITY =====\n'
printf 'run=%s\n' "$RUN_ROOT"
printf 'grid=%sx%s gamma=%s dt=%s steps=%s\n' "$NX" "$NY" "$GAMMA" "$DT" "$STEPS"
printf 'slab=%s cells alpha=%s bodyAx=%s Darcy=%s chiVP=%s strength=%s layers=%s\n' "$SLAB_CELLS" "$ALPHA" "$BODY_AX" "$DARCY_BRINKMAN_FORCING_MODE" "$DARCY_CHI_COLLISION_VP_ENABLE" "$DARCY_CHI_COLLISION_VP_STRENGTH" "$DARCY_CHI_COLLISION_VP_LAYERS"
printf 'LiveVis+recorder: control=%s enable=%s every=%s fields=%s grid=%sx%s recordEvery=%s\n' "$LIVE_VIS_CONTROL_FILE" "$LIVE_VIS_ENABLE" "$LIVE_VIS_EVERY" "$RECORD_FIELDS" "$LIVE_VIS_NX" "$LIVE_VIS_NY" "$RECORD_EVERY"
printf 'restart=%s dumpEvery=%s\n' "$RESTART" "$DUMP_STATE_EVERY"
printf '===================================================\n\n'

suite_run_binary_0434 "$PARAMS" "$LOG" "$TIMEFILE" "$OUT" || exit $?

if suite_truthy_0434 "$PREFLIGHT_ONLY"; then exit 0; fi
[[ -s "$OUT/chi_solid_impulse_0493x15a.csv" ]] || { echo "[0493x15c] ERROR missing chi_solid_impulse_0493x15a.csv" >&2; exit 2; }
[[ -s "$OUT/chi_vp_impulse_0493x15b.csv" ]] || { echo "[0493x15c] ERROR missing chi_vp_impulse_0493x15b.csv" >&2; exit 2; }
[[ -s "$OUT/chi_permeability_0493x15c.csv" ]] || { echo "[0493x15c] ERROR missing chi_permeability_0493x15c.csv" >&2; exit 2; }
[[ -s "$OUT/summary_runtime.csv" ]] || { echo "[0493x15c] ERROR missing summary_runtime.csv" >&2; exit 2; }

echo "[0493x15c] COMPLETE run=$RUN_ROOT"
echo "[0493x15c] next: analyze from matlab/ with analyze_0493x15c_chi_vp_permeability('../runs/...')"
