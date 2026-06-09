#!/usr/bin/env bash
set -euo pipefail

# 0312 — independent inactive-slot scaling audit.
# This runner deliberately does NOT call any run_demo_* script or source the
# demo common helpers.  It writes states, params, CUDA environment and logs
# itself so local edits of visual/demo scripts cannot affect audit results.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BIN=${BIN:-build/src_mpcd_base_cuda_0312}
ART_DIR=${ART_DIR:-dev_history/artifacts/gpu_cuda_inactive_slots_independent_0312}
FORCE_REBUILD=${FORCE_REBUILD:-1}
STOP_ON_FAIL=${STOP_ON_FAIL:-0}
CLEAN_ART_DIR=${CLEAN_ART_DIR:-1}
LIVE_PROGRESS=${LIVE_PROGRESS:-0}

THREADS=${THREADS:-8}
GAMMA=${GAMMA:-20}
KBT=${KBT:-0.001}
SUMMARY_EVERY=${SUMMARY_EVERY:-100}
DUMP_STATE_EVERY=${DUMP_STATE_EVERY:-999999}
THERMOSTAT_ENABLE=${THERMOSTAT_ENABLE:-1}

# Short default sweep.  250000 is intentionally not included by default.
INACTIVE_SLOTS_GRID=${INACTIVE_SLOTS_GRID:-"8000 20000 50000 100000"}
MODES=${MODES:-"resampling"}       # classic resampling
RUN_STEP=${RUN_STEP:-1}
RUN_VK=${RUN_VK:-0}

STEP_NX=${STEP_NX:-96}; STEP_NY=${STEP_NY:-48}; STEP_STEPS=${STEP_STEPS:-400}; STEP_DT=${STEP_DT:-0.0008}; STEP_UIN=${STEP_UIN:-0.45}
VK_NX=${VK_NX:-96}; VK_NY=${VK_NY:-48}; VK_STEPS=${VK_STEPS:-400}; VK_DT=${VK_DT:-0.0005}; VK_UIN=${VK_UIN:-0.45}; VK_OUTLET_MODE=${VK_OUTLET_MODE:-equilibrium_flux}

GUARD_EVERY=${GUARD_EVERY:-20}
GUARD_NMIN=${GUARD_NMIN:-12}
GUARD_NTARGET=${GUARD_NTARGET:-20}
GUARD_NMAX=${GUARD_NMAX:-32}
GUARD_SPLIT_FRACTION=${GUARD_SPLIT_FRACTION:-0.5}
MASS_RECONDITION_ENABLE=${MASS_RECONDITION_ENABLE:-1}
MASS_RECONDITION_EVERY=${MASS_RECONDITION_EVERY:-$GUARD_EVERY}
MASS_RECONDITION_STRENGTH=${MASS_RECONDITION_STRENGTH:-1.0}
RESTORE_ENABLE=${RESTORE_ENABLE:-1}
BOUNDARY_AWARE=${BOUNDARY_AWARE:-1}
OPEN_BOUNDARY_HALO_CELLS=${OPEN_BOUNDARY_HALO_CELLS:-1}
BOUNDARY_HALO_CELLS=${BOUNDARY_HALO_CELLS:-0}
SOLID_HALO_CELLS=${SOLID_HALO_CELLS:-0}
SPLIT_SAFETY=${SPLIT_SAFETY:-1}
SPLIT_PREFER_MAX_MASS_DONOR=${SPLIT_PREFER_MAX_MASS_DONOR:-1}
SPLIT_DONOR_MIN_MASS=${SPLIT_DONOR_MIN_MASS:-0.5}
SPLIT_NEW_PARTICLE_MIN_MASS=${SPLIT_NEW_PARTICLE_MIN_MASS:-0.25}
SOLID_ADJACENT_SPLIT_MODE=${SOLID_ADJACENT_SPLIT_MODE:-0}

export OMP_NUM_THREADS=${OMP_NUM_THREADS:-$THREADS}
export OMP_PROC_BIND=${OMP_PROC_BIND:-close}
export OMP_PLACES=${OMP_PLACES:-cores}
export OMP_DYNAMIC=${OMP_DYNAMIC:-false}

if [[ "$CLEAN_ART_DIR" == "1" || "$CLEAN_ART_DIR" == "true" || "$CLEAN_ART_DIR" == "TRUE" ]]; then
  rm -rf "$ART_DIR"
fi
mkdir -p "$ART_DIR"

if [[ "$FORCE_REBUILD" != "0" && "$FORCE_REBUILD" != "false" && "$FORCE_REBUILD" != "FALSE" ]]; then
  OUT="$BIN" CUDA_ARCH_FLAGS="${CUDA_ARCH_FLAGS:-}" bash scripts/build_src_mpcd_cuda_0312.sh
elif [[ ! -x "$BIN" ]]; then
  OUT="$BIN" CUDA_ARCH_FLAGS="${CUDA_ARCH_FLAGS:-}" bash scripts/build_src_mpcd_cuda_0312.sh
fi

RUN_MANIFEST="$ART_DIR/cuda_inactive_slots_independent_0312_run_manifest.csv"
printf 'caseName,modeName,inactiveSlotsRequested,runRoot,requestedSteps,exitCode,logFile,timeFile,paramsFile,summaryFile,extraEnv\n' > "$RUN_MANIFEST"

append_manifest() {
  python3 - "$RUN_MANIFEST" "$@" <<'PY'
import csv, sys
with open(sys.argv[1], 'a', newline='') as fh:
    csv.writer(fh).writerow(sys.argv[2:])
PY
}

bool_true_0312() {
  case "${1:-0}" in 1|true|TRUE|yes|YES|on|ON) return 0 ;; *) return 1 ;; esac
}

clear_cuda_env_0312() {
  export MPCD_CUDA_CLASSIC_SRC_PERIODIC_RESIDENT_0260=0
  export MPCD_CUDA_CLASSIC_SRC_WALL_RESIDENT_0261=0
  export MPCD_CUDA_CLASSIC_SRC_SOLID_RESIDENT_0262=0
  export MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263=0
  export MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263_STRICT=0
  export MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264=0
  export MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264_STRICT=0
  export MPCD_CUDA_STREAMING_PERIODIC_0245=0
  export MPCD_CUDA_STREAMING_WALL_SIMPLE_0246=0
  export MPCD_CUDA_IMMERSED_RECTANGLE_0247=0
  export MPCD_CUDA_IMMERSED_CIRCLE_0284=0
  export MPCD_CUDA_IMMERSED_RECTANGLE_0247_DOWNLOAD_ALL=0
  export MPCD_CUDA_IMMERSED_CIRCLE_0284_DOWNLOAD_ALL=0
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=0
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_STRICT=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_ACTIVE_STRICT=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_MINIMAL_DOWNLOAD_0257=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251=0
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_WALL_SIMPLE_0253=0
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_IMMERSED_RECT_0254=0
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_IMMERSED_CIRCLE_0284=0
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_DEVICE_ROTATION_0272=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WORKSPACE_DOWNLOAD_0272=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_FINAL_SYNC_0272=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_LAZY_KERNEL_CHECK_0273=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_SETUP_SYNC_0273=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_FUSED_STREAM_DEPOSIT_0274=1
  export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE=0
  export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_STRICT=1
  export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_CONSUME_STRICT=1
  export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260=0
  export MPCD_CUDA_PERSISTENT_PARTICLE_STATE_USE=1
  export MPCD_CUDA_PERSISTENT_PARTICLE_METADATA_CACHE=1
  export MPCD_CUDA_PERSISTENT_CELL_WORKSPACE_USE=1
  export MPCD_CUDA_PERSISTENT_THREADS_PER_BLOCK=${MPCD_CUDA_PERSISTENT_THREADS_PER_BLOCK:-256}
  export MPCD_CUDA_RESAMPLING_SUPPORT_SURVEY_0295=0
  export MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296=0
  export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297=0
  export MPCD_CUDA_RESAMPLING_MOMENT_RESTORE_0298=0
  export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0299_BOUNDARY_AWARE=0
  export MPCD_CUDA_RESAMPLING_SPLIT_SAFETY_0307=0
  export MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304=0
}

enable_cuda_io_step_0312() {
  clear_cuda_env_0312
  export MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263=1
  export MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263_STRICT=1
  export MPCD_CUDA_IMMERSED_RECTANGLE_0247=1
  export MPCD_CUDA_IMMERSED_RECTANGLE_0247_DOWNLOAD_ALL=0
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_WALL_SIMPLE_0253=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_IMMERSED_RECT_0254=1
  if bool_true_0312 "$THERMOSTAT_ENABLE"; then
    export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE=1
    export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260=1
  fi
}

enable_cuda_io_circle_0312() {
  clear_cuda_env_0312
  export MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263=1
  export MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263_STRICT=1
  export MPCD_CUDA_IMMERSED_CIRCLE_0284=1
  export MPCD_CUDA_IMMERSED_CIRCLE_0284_DOWNLOAD_ALL=0
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_STRICT=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_WALL_SIMPLE_0253=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_IMMERSED_CIRCLE_0284=1
  if bool_true_0312 "$THERMOSTAT_ENABLE"; then
    export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE=1
    export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260=1
  fi
}

enable_resampling_0312() {
  local mode="$1"
  if [[ "$mode" != "resampling" ]]; then
    return 0
  fi
  export MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296="$MASS_RECONDITION_ENABLE"
  export MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296_EVERY="$MASS_RECONDITION_EVERY"
  export MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296_STRENGTH="$MASS_RECONDITION_STRENGTH"
  export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297=1
  export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_EVERY="$GUARD_EVERY"
  export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_NMIN="$GUARD_NMIN"
  export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_NTARGET="$GUARD_NTARGET"
  export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_NMAX="$GUARD_NMAX"
  export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_SPLIT_FRACTION="$GUARD_SPLIT_FRACTION"
  export MPCD_CUDA_RESAMPLING_MOMENT_RESTORE_0298="$RESTORE_ENABLE"
  export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0299_BOUNDARY_AWARE="$BOUNDARY_AWARE"
  export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0299_OPEN_BOUNDARY_HALO_CELLS="$OPEN_BOUNDARY_HALO_CELLS"
  export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0299_BOUNDARY_HALO_CELLS="$BOUNDARY_HALO_CELLS"
  export MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0299_SOLID_HALO_CELLS="$SOLID_HALO_CELLS"
  export MPCD_CUDA_RESAMPLING_SPLIT_SAFETY_0307="$SPLIT_SAFETY"
  export MPCD_CUDA_RESAMPLING_SPLIT_PREFER_MAX_MASS_DONOR_0307="$SPLIT_PREFER_MAX_MASS_DONOR"
  export MPCD_CUDA_RESAMPLING_SPLIT_DONOR_MIN_MASS_0307="$SPLIT_DONOR_MIN_MASS"
  export MPCD_CUDA_RESAMPLING_SPLIT_NEW_PARTICLE_MIN_MASS_0307="$SPLIT_NEW_PARTICLE_MIN_MASS"
  export MPCD_CUDA_RESAMPLING_SOLID_ADJACENT_SPLIT_MODE_0307="$SOLID_ADJACENT_SPLIT_MODE"
}

thermostat_kv_0312() { if bool_true_0312 "$THERMOSTAT_ENABLE"; then printf true; else printf false; fi; }

write_common_tail_0312() {
  local steps="$1" dt="$2" seed="$3"
  cat <<PARAMS
nSteps = ${steps}
dt = ${dt}
rotationAngle = 1.5
randomRotationSign = true
gridShiftEnable = true
rngSeed = ${seed}

srcClassicCudaModeEnable = true
projectionEnable = false
resamplingEnable = false
closedCapacityResponseEnable = false
closedCapacityVirialKickEnable = false

thermostatEnable = $(thermostat_kv_0312)
thermostatMode = cell_relative_rescale
thermostatEvery = 1
thermostatTargetKBT = -1.0
thermostatMinParticles = 3
kBT = ${KBT}

summaryEvery = ${SUMMARY_EVERY}
dumpStateEvery = ${DUMP_STATE_EVERY}
numThreads = ${THREADS}
PARAMS
}

write_backward_step_params_0312() {
  local params="$1" state="$2" out="$3" steps="$4" dt="$5" uin="$6"
  cat > "$params" <<PARAMS
inputState = ${state}
outputDir = ${out}

Lx = 3.0
Ly = 1.0
Nx = ${STEP_NX}
Ny = ${STEP_NY}

bcLeft = inlet
bcRight = outlet
bcBottom = solid
bcTop = solid

bodyAccelerationX = 0.0
bodyAccelerationY = 0.0
taylorGreenForcingEnable = false

inletUxLeft = ${uin}
inletUyLeft = 0.0
inletVelocityRampEnable = true
inletVelocityRampStartTime = 0.0
inletVelocityRampEndTime = 0.25
inletVelocityRampInitialFactor = 0.2
inletVelocityRampFinalFactor = 1.0
inletVelocityRampProfile = smoothstep
inletVelocitySpatialProfile = flat_taper_y
inletVelocityWallTaperCells = 2.0
inletKBT = -1.0
inletThermalNoise = 0.0
inletInjectionMode = hard_cell_density
inletReservoirMode = hard_cell_density
inletReservoirCells = 3
inletTargetOccupancy = ${GAMMA}
inletHardCellVelocityMean = true
inletHardCellThermalRescale = true
inletRandomizeTangential = true
inletReinjectBackflow = true

openBoundaryOutletMode = hybrid
openBoundaryOutletHybridBlend = 0.0
openBoundaryOutletFeedbackGain = 0.0

immersedSolidEnable = true
immersedSolidShape = rectangle
immersedSolidXMin = 0.0
immersedSolidXMax = 0.5
immersedSolidYMin = 0.0
immersedSolidYMax = 0.42
immersedSolidFractionSamples = 4
immersedSolidVx = 0.0
immersedSolidVy = 0.0
immersedSolidWallUx = 0.0
immersedSolidWallUy = 0.0
immersedSolidOmega = 0.0

wallAccommodation = 1.0
wallVpGamma = ${GAMMA}
wallVpMass = 1.0
wallKBT = -1.0
wallThermalNoise = 0.0

$(write_common_tail_0312 "$steps" "$dt" 1629312)
PARAMS
}

write_vk_params_0312() {
  local params="$1" state="$2" out="$3" steps="$4" dt="$5" uin="$6"
  cat > "$params" <<PARAMS
inputState = ${state}
outputDir = ${out}

Lx = 3.0
Ly = 1.0
Nx = ${VK_NX}
Ny = ${VK_NY}

bcLeft = inlet
bcRight = outlet
bcBottom = solid
bcTop = solid

bodyAccelerationX = 0.0
bodyAccelerationY = 0.0
taylorGreenForcingEnable = false
keepMeanFlowEnable = false

inletUxLeft = ${uin}
inletUyLeft = 0.0
inletVelocityRampEnable = true
inletVelocityRampStartTime = 0.0
inletVelocityRampEndTime = 0.25
inletVelocityRampInitialFactor = 0.2
inletVelocityRampFinalFactor = 1.0
inletVelocityRampProfile = smoothstep
inletVelocitySpatialProfile = flat_taper_y
inletVelocityWallTaperCells = 2.0
inletKBT = -1.0
inletThermalNoise = 0.0
inletInjectionMode = hard_cell_density
inletReservoirMode = hard_cell_density
inletReservoirCells = 3
inletTargetOccupancy = ${GAMMA}
inletHardCellVelocityMean = true
inletHardCellThermalRescale = true
inletRandomizeTangential = true
inletReinjectBackflow = true

openBoundaryOutletMode = ${VK_OUTLET_MODE}
openBoundaryOutletHybridBlend = 0.0
openBoundaryOutletFeedbackGain = 0.0

immersedSolidEnable = true
immersedSolidShape = circle
immersedSolidCx = 0.65
immersedSolidCy = 0.50
immersedSolidR = 0.12
immersedSolidFractionSamples = 4
immersedSolidVx = 0.0
immersedSolidVy = 0.0
immersedSolidWallUx = 0.0
immersedSolidWallUy = 0.0
immersedSolidOmega = 0.0

wallAccommodation = 1.0
wallVpGamma = ${GAMMA}
wallVpMass = 1.0
wallKBT = -1.0
wallThermalNoise = 0.0

$(write_common_tail_0312 "$steps" "$dt" 1629313)
PARAMS
}

run_one_0312() {
  local case_name="$1" mode="$2" slots="$3"
  local nx ny steps dt uin rect circle state_mode
  if [[ "$case_name" == "backward_step" ]]; then
    nx="$STEP_NX"; ny="$STEP_NY"; steps="$STEP_STEPS"; dt="$STEP_DT"; uin="$STEP_UIN"; rect="0.0,0.5,0.0,0.42"; circle="none"; state_mode="uniform"
  else
    nx="$VK_NX"; ny="$VK_NY"; steps="$VK_STEPS"; dt="$VK_DT"; uin="$VK_UIN"; rect="none"; circle="0.65,0.50,0.12"; state_mode="uniform"
  fi
  local run_root="$ART_DIR/$case_name/${mode}_inactive_${slots}"
  rm -rf "$run_root"
  mkdir -p "$run_root/init" "$run_root/params" "$run_root/output" "$run_root/logs"
  local state="$run_root/init/${case_name}_${nx}x${ny}_g${GAMMA}_inactive${slots}.smpcd"
  local params="$run_root/params/${case_name}.kv"
  local out="$run_root/output"
  local log="$run_root/logs/${case_name}.log"
  local time_file="$run_root/logs/${case_name}.time"
  local gen_log="$run_root/logs/generate_state.log"

  python3 scripts/generate_src_gpu_audit_state_0312.py \
    --output "$state" --Lx 3.0 --Ly 1.0 --Nx "$nx" --Ny "$ny" --gamma "$GAMMA" --kBT "$KBT" \
    --seed 1629312 --velocity-mode "$state_mode" --mean-ux "$uin" --mean-uy 0.0 --inactive-slots "$slots" \
    --rect "$rect" --circle "$circle" > "$gen_log" 2>&1

  if [[ "$case_name" == "backward_step" ]]; then
    write_backward_step_params_0312 "$params" "$state" "$out" "$steps" "$dt" "$uin"
    enable_cuda_io_step_0312
  else
    write_vk_params_0312 "$params" "$state" "$out" "$steps" "$dt" "$uin"
    enable_cuda_io_circle_0312
  fi
  enable_resampling_0312 "$mode"

  echo "[0312-independent] case=$case_name mode=$mode inactiveSlots=$slots steps=$steps runRoot=$run_root"
  local rc=0
  set +e
  if [[ "$LIVE_PROGRESS" == "1" || "$LIVE_PROGRESS" == "true" || "$LIVE_PROGRESS" == "TRUE" ]]; then
    /usr/bin/time -f 'elapsed=%e user=%U sys=%S' "$BIN" "$params" 2> "$time_file" | tee "$log"
    rc=${PIPESTATUS[0]}
  else
    /usr/bin/time -f 'elapsed=%e user=%U sys=%S' "$BIN" "$params" > "$log" 2> "$time_file"
    rc=$?
  fi
  set -e
  append_manifest "$case_name" "$mode" "$slots" "$run_root" "$steps" "$rc" "$log" "$time_file" "$params" "$out/summary_runtime.csv" "guardEvery=$GUARD_EVERY;independent=1"
  if [[ "$rc" != "0" ]]; then
    echo "[0312-independent] FAIL case=$case_name mode=$mode slots=$slots rc=$rc" >&2
    tail -60 "$time_file" >&2 || true
    tail -60 "$log" >&2 || true
    if [[ "$STOP_ON_FAIL" == "1" ]]; then exit "$rc"; fi
  fi
}

for case_name in backward_step von_karman_circle; do
  if [[ "$case_name" == "backward_step" && "$RUN_STEP" == "0" ]]; then continue; fi
  if [[ "$case_name" == "von_karman_circle" && "$RUN_VK" == "0" ]]; then continue; fi
  for mode in $MODES; do
    for slots in $INACTIVE_SLOTS_GRID; do
      run_one_0312 "$case_name" "$mode" "$slots"
    done
  done
done

python3 scripts/analyze_cuda_inactive_slots_independent_audit_0312.py "$RUN_MANIFEST" "$ART_DIR"

echo "[0312-independent] manifest=$RUN_MANIFEST"
echo "[0312-independent] per-run=$ART_DIR/cuda_inactive_slots_independent_0312_per_run.csv"
echo "[0312-independent] ratios=$ART_DIR/cuda_inactive_slots_independent_0312_ratios.csv"
