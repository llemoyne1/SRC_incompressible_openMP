#!/usr/bin/env bash
set -euo pipefail

# 0317d — phase profiling harness after 0317b.
# Script-only: no solver source modification.  It compensates for Nsight Systems
# installations that can record .qdstrm traces but cannot import/export stats,
# by enabling the existing opt-in SRC phase profilers only during this run.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ART_DIR=${ART_DIR:-dev_history/artifacts/gpu_phase_profile_0317d}
CLEAN_ART_DIR=${CLEAN_ART_DIR:-1}
RUN_SRC_PERIODIC=${RUN_SRC_PERIODIC:-1}
RUN_SRC_IO=${RUN_SRC_IO:-1}
RUN_VKKH=${RUN_VKKH:-1}
WARMUP=${WARMUP:-1}
REPEATS=${REPEATS:-1}

# Comparable VK defaults. Override from the shell if needed.
Lx=${Lx:-3.0}; Ly=${Ly:-1.0}; NX=${NX:-192}; NY=${NY:-64}; GAMMA=${GAMMA:-20}
STEPS=${STEPS:-10000}; WARMUP_STEPS=${WARMUP_STEPS:-1000}
DT=${DT:-0.001}; KBT=${KBT:-0.001}; UIN=${UIN:-0.2}; SEED=${SEED:-1628505}
CYLINDER_CX=${CYLINDER_CX:-0.65}; CYLINDER_CY=${CYLINDER_CY:-0.50}; CYLINDER_R=${CYLINDER_R:-0.15}
THREADS=${THREADS:-8}; INACTIVE_SLOTS=${INACTIVE_SLOTS:-100000}

SRC_BIN=${SRC_BIN:-build/src_mpcd_base_cuda_0315m_profile}
SRC_BUILD=${SRC_BUILD:-0}
SRC_BUILD_SCRIPT=${SRC_BUILD_SCRIPT:-scripts/build_src_mpcd_cuda_0315b.sh}
SRC_PERIODIC_RUN_SCRIPT=${SRC_PERIODIC_RUN_SCRIPT:-scripts/run_demo_src_classic_cuda_von_karman_cylinder_0285.sh}

# Existing opt-in profilers in the solver.  They are disabled by default in normal runs.
SRC_INTERNAL_PROFILES=${SRC_INTERNAL_PROFILES:-1}
SRC_CUDA_RESIDENT_PROFILE=${SRC_CUDA_RESIDENT_PROFILE:-1}

# Standalone comparison source.
VKKH_CU=${VKKH_CU:-mpcd_vkkh_play.cu}
VKKH_BIN=${VKKH_BIN:-build/mpcd_vkkh_play_0317c}
VKKH_BUILD=${VKKH_BUILD:-0}

TIME_BIN=${TIME_BIN:-/usr/bin/time}

if [[ "$CLEAN_ART_DIR" == "1" || "$CLEAN_ART_DIR" == "true" || "$CLEAN_ART_DIR" == "TRUE" ]]; then
  rm -rf "$ART_DIR"
fi
mkdir -p "$ART_DIR" "$ART_DIR/logs" "$ART_DIR/time" "$ART_DIR/runs"

if [[ "$SRC_BUILD" == "1" && ( "$RUN_SRC_PERIODIC" == "1" || "$RUN_SRC_IO" == "1" ) ]]; then
  if [[ ! -f "$SRC_BUILD_SCRIPT" ]]; then
    SRC_BUILD_SCRIPT="scripts/build_src_mpcd_cuda_0293.sh"
  fi
  echo "[0317d-profile] building SRC binary: $SRC_BIN via $SRC_BUILD_SCRIPT"
  OUT="$SRC_BIN" CUDA_ARCH_FLAGS="${CUDA_ARCH_FLAGS:-}" bash "$SRC_BUILD_SCRIPT"
fi
if [[ ( "$RUN_SRC_PERIODIC" == "1" || "$RUN_SRC_IO" == "1" ) && ! -x "$SRC_BIN" ]]; then
  echo "[0317d-profile] ERROR: SRC_BIN missing/not executable: $SRC_BIN" >&2
  exit 127
fi

if [[ "$RUN_VKKH" == "1" ]]; then
  if [[ ! -f "$VKKH_CU" ]]; then
    echo "[0317d-profile] WARNING: VKKH_CU not found: $VKKH_CU" >&2
    echo "[0317d-profile]          Set VKKH_CU=/path/to/mpcd_vkkh_play.cu, or RUN_VKKH=0." >&2
    RUN_VKKH=0
  elif [[ "$VKKH_BUILD" == "1" ]]; then
    echo "[0317d-profile] building VKKH binary: $VKKH_BIN from $VKKH_CU"
    mkdir -p "$(dirname "$VKKH_BIN")"
    nvcc ${VKKH_NVCCFLAGS:--O3 -std=c++17} ${CUDA_ARCH_FLAGS:-} -Xcompiler -fopenmp "$VKKH_CU" -o "$VKKH_BIN"
  fi
fi
if [[ "$RUN_VKKH" == "1" && ! -x "$VKKH_BIN" ]]; then
  echo "[0317d-profile] ERROR: VKKH_BIN missing/not executable: $VKKH_BIN" >&2
  exit 127
fi

MANIFEST="$ART_DIR/gpu_phase_profile_0317d_manifest.csv"
printf 'target,repeat,steps,nx,ny,gamma,binary,runRoot,timeFile,stdoutFile,stderrFile,exitCode,note\n' > "$MANIFEST"
append_manifest() {
  python3 - "$MANIFEST" "$@" <<'PY'
import csv, sys
with open(sys.argv[1], 'a', newline='') as f:
    csv.writer(f).writerow(sys.argv[2:])
PY
}

run_time_only() {
  local time_file=$1 stdout_file=$2 stderr_file=$3
  shift 3
  "$TIME_BIN" -f 'elapsed_seconds,%e\nuser_seconds,%U\nsys_seconds,%S\nmax_rss_kb,%M\nexit_code,%x' -o "$time_file" \
    "$@" >"$stdout_file" 2>"$stderr_file"
}

make_src_periodic_helper() {
  local helper=$1 run_root=$2 steps=$3
  cat > "$helper" <<EOF_HELPER
#!/usr/bin/env bash
set -euo pipefail
cd "$ROOT"
env BIN="$SRC_BIN" AUTO_BUILD=0 LIVE_PROGRESS=0 CLEAN_RUN_ROOT=1 \\
  RUN_ROOT="$run_root" Lx="$Lx" Ly="$Ly" NX="$NX" NY="$NY" GAMMA="$GAMMA" STEPS="$steps" DT="$DT" KBT="$KBT" SEED="$SEED" \\
  UIN="$UIN" CYLINDER_CX="$CYLINDER_CX" CYLINDER_CY="$CYLINDER_CY" CYLINDER_R="$CYLINDER_R" \\
  INACTIVE_SLOTS="$INACTIVE_SLOTS" THREADS="$THREADS" \\
  SUMMARY_EVERY=1000000000 DUMP_STATE_EVERY=0 SRC_GPU_DEMO_REQUIRE_DUMPS=0 DUMP_ROLE_FILTER=fluid SUMMARY_ROLE_FILTER=fluid \\
  RESAMPLING_ENABLE=0 RESAMPLING_SURVEY_ENABLE=0 GUARD_EVERY=999999 \\
  MPCD_INTERNAL_PROFILES="$SRC_INTERNAL_PROFILES" MPCD_CUDA_RESIDENT_PROFILE_0266="$SRC_CUDA_RESIDENT_PROFILE" \\
  bash "$SRC_PERIODIC_RUN_SCRIPT"
EOF_HELPER
  chmod +x "$helper"
}

make_src_io_helper() {
  local helper=$1 run_root=$2 steps=$3
  {
    printf '%s\n' '#!/usr/bin/env bash'
    printf '%s\n' 'set -euo pipefail'
    printf 'ROOT=%q\n' "$ROOT"
    printf 'SRC_BIN=%q\n' "$SRC_BIN"
    printf 'RUN_ROOT_0317D=%q\n' "$run_root"
    printf 'Lx=%q\n' "$Lx"
    printf 'Ly=%q\n' "$Ly"
    printf 'NX=%q\n' "$NX"
    printf 'NY=%q\n' "$NY"
    printf 'GAMMA=%q\n' "$GAMMA"
    printf 'STEPS_0317D=%q\n' "$steps"
    printf 'DT=%q\n' "$DT"
    printf 'KBT=%q\n' "$KBT"
    printf 'SEED=%q\n' "$SEED"
    printf 'UIN=%q\n' "$UIN"
    printf 'THREADS=%q\n' "$THREADS"
    printf 'INACTIVE_SLOTS=%q\n' "$INACTIVE_SLOTS"
    printf 'CYLINDER_CX=%q\n' "$CYLINDER_CX"
    printf 'CYLINDER_CY=%q\n' "$CYLINDER_CY"
    printf 'CYLINDER_R=%q\n' "$CYLINDER_R"
    printf 'SRC_INTERNAL_PROFILES=%q\n' "$SRC_INTERNAL_PROFILES"
    printf 'SRC_CUDA_RESIDENT_PROFILE=%q\n' "$SRC_CUDA_RESIDENT_PROFILE"
    cat <<'EOF_HELPER'
cd "$ROOT"
source scripts/src_gpu_demo_common_0283.sh
BIN="$SRC_BIN"
AUTO_BUILD=0
LIVE_PROGRESS=0
CLEAN_RUN_ROOT=1
THREADS="$THREADS"
OMP_NUM_THREADS="$THREADS"
export OMP_NUM_THREADS OMP_PROC_BIND OMP_PLACES OMP_DYNAMIC
CASE_NAME="vk_like_io_0317d"
prepare_demo_dirs_0283 "$RUN_ROOT_0317D"
STATE_FILE="$RUN_ROOT_0317D/init/vk_like_io_${NX}x${NY}_g${GAMMA}.smpcd"
PARAMS_FILE="$RUN_ROOT_0317D/params/vk_like_io.kv"
OUT_DIR="$RUN_ROOT_0317D/output"
LOG_FILE="$RUN_ROOT_0317D/logs/vk_like_io.log"
TIME_FILE="$RUN_ROOT_0317D/logs/vk_like_io.time"
generate_demo_state_0283 "$STATE_FILE" "$Lx" "$Ly" "$NX" "$NY" "$GAMMA" "$KBT" "$SEED" uniform "$UIN" 0.0 0.0 0.0 -1.0 0.0 -1.0 "$INACTIVE_SLOTS" "circle:${CYLINDER_CX},${CYLINDER_CY},${CYLINDER_R}"
mkdir -p "$OUT_DIR"
DUMP_ROLE_FILTER=fluid
SUMMARY_ROLE_FILTER=fluid
export DUMP_ROLE_FILTER SUMMARY_ROLE_FILTER
cat > "$PARAMS_FILE" <<PARAMS
inputState = ${STATE_FILE}
outputDir = ${OUT_DIR}

Lx = ${Lx}
Ly = ${Ly}
Nx = ${NX}
Ny = ${NY}

bcLeft = inlet
bcRight = outlet
bcBottom = solid
bcTop = solid

bodyAccelerationX = 0.0
bodyAccelerationY = 0.0
taylorGreenForcingEnable = false
keepMeanFlowEnable = false

inletUxLeft = ${UIN}
inletUyLeft = 0.0
inletVelocityRampEnable = false
inletVelocityRampStartTime = 0.0
inletVelocityRampEndTime = 0.0
inletVelocityRampInitialFactor = 1.0
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

openBoundaryOutletMode = equilibrium_flux
openBoundaryOutletForcedMassFlux = 0.0
openBoundaryOutletForcedMassPerStep = 0.0
openBoundaryOutletForcedParticleFlux = 0.0
openBoundaryOutletForcedParticlesPerStep = 0
openBoundaryOutletForcedLayerCells = 3
openBoundaryOutletHybridBlend = 0.0
openBoundaryOutletFeedbackGain = 0.0

immersedSolidEnable = true
immersedSolidShape = circle
immersedSolidCx = ${CYLINDER_CX}
immersedSolidCy = ${CYLINDER_CY}
immersedSolidR = ${CYLINDER_R}
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

$(write_src_classic_common_params_0283 "$STEPS_0317D" "$DT" "$KBT" "$SEED" 1000000000 0 "$THREADS" 1.5)
PARAMS
src_gpu_cuda_env_clear_0283
export MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263=1
export MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263_STRICT=1
export MPCD_CUDA_IMMERSED_CIRCLE_0284=1
export MPCD_CUDA_IMMERSED_CIRCLE_0284_DOWNLOAD_ALL=0
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=1
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_STRICT=1
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_ACTIVE_STRICT=1
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_MINIMAL_DOWNLOAD_0257=1
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_WALL_SIMPLE_0253=1
export MPCD_CUDA_PERSISTENT_SRC_COLLISION_IMMERSED_CIRCLE_0284=1
export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE=1
export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_STRICT=1
export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260=1
export MPCD_CUDA_PERSISTENT_THREADS_PER_BLOCK="${MPCD_CUDA_PERSISTENT_THREADS_PER_BLOCK:-256}"
export MPCD_INTERNAL_PROFILES="$SRC_INTERNAL_PROFILES"
export MPCD_CUDA_RESIDENT_PROFILE_0266="$SRC_CUDA_RESIDENT_PROFILE"
run_demo_case_0283 "$PARAMS_FILE" "$LOG_FILE" "$TIME_FILE" "$OUT_DIR"
EOF_HELPER
  } > "$helper"
  chmod +x "$helper"
}
make_vkkh_helper() {
  local helper=$1 run_root=$2 steps=$3
  cat > "$helper" <<EOF_HELPER
#!/usr/bin/env bash
set -euo pipefail
cd "$ROOT"
mkdir -p "$run_root/output"
"$VKKH_BIN" --mode vk --Lx "$Lx" --Ly "$Ly" --Nx "$NX" --Ny "$NY" --gamma "$GAMMA" \\
  --steps "$steps" --dt "$DT" --kBT "$KBT" --U0 "$UIN" --seed "$SEED" \\
  --xc "$CYLINDER_CX" --yc "$CYLINDER_CY" --Rc "$CYLINDER_R" \\
  --thermostat 1 --keepMeanFlow 0 --xInletInject 1 --reinjectBackflow 1 --injectRandomY 1 \\
  --solid 1 --vis 0 --writeCSV 0 --dumpStride 1000000000 --logStride 1000000000 \\
  --outDir "$run_root/output"
EOF_HELPER
  chmod +x "$helper"
}

run_target() {
  local target=$1 rep=$2 steps=$3 warm=$4
  local run_root="$ART_DIR/runs/${target}/rep_${rep}"
  if [[ "$warm" == "1" ]]; then run_root="$ART_DIR/warmup_${target}"; fi
  local time_file="$ART_DIR/time/${target}_rep_${rep}.time.csv"
  local stdout_file="$ART_DIR/logs/${target}_rep_${rep}.stdout.log"
  local stderr_file="$ART_DIR/logs/${target}_rep_${rep}.stderr.log"
  local helper="$ART_DIR/run_${target}_rep_${rep}.sh"
  if [[ "$warm" == "1" ]]; then
    time_file="$ART_DIR/time/warmup_${target}.time.csv"
    stdout_file="$ART_DIR/logs/warmup_${target}.stdout.log"
    stderr_file="$ART_DIR/logs/warmup_${target}.stderr.log"
    helper="$ART_DIR/warmup_${target}.sh"
  fi
  mkdir -p "$run_root"
  case "$target" in
    src_cuda_v2_0315m_periodic) make_src_periodic_helper "$helper" "$run_root" "$steps" ;;
    src_cuda_v2_0315m_io) make_src_io_helper "$helper" "$run_root" "$steps" ;;
    mpcd_vkkh_play) make_vkkh_helper "$helper" "$run_root" "$steps" ;;
    *) echo "[0317d-profile] unknown target=$target" >&2; exit 2 ;;
  esac
  echo "[0317d-profile] run target=$target rep=$rep steps=$steps warmup=$warm"
  set +e
  run_time_only "$time_file" "$stdout_file" "$stderr_file" "$helper"
  local rc=$?
  set -e
  if [[ "$warm" != "1" ]]; then
    local bin="$SRC_BIN"
    [[ "$target" == "mpcd_vkkh_play" ]] && bin="$VKKH_BIN"
    append_manifest "$target" "$rep" "$steps" "$NX" "$NY" "$GAMMA" "$bin" "$run_root" "$time_file" "$stdout_file" "$stderr_file" "$rc" "internal_profiles_src_only=${SRC_INTERNAL_PROFILES}"
  fi
  if [[ "$rc" != "0" ]]; then
    echo "[0317d-profile] WARNING: target=$target rep=$rep failed rc=$rc" >&2
    tail -80 "$stderr_file" >&2 || true
  fi
}

if [[ "$WARMUP" == "1" ]]; then
  echo "[0317d-profile] warmups use WARMUP_STEPS=$WARMUP_STEPS and are excluded from manifest."
  [[ "$RUN_SRC_PERIODIC" == "1" ]] && run_target src_cuda_v2_0315m_periodic 0 "$WARMUP_STEPS" 1
  [[ "$RUN_SRC_IO" == "1" ]] && run_target src_cuda_v2_0315m_io 0 "$WARMUP_STEPS" 1
  [[ "$RUN_VKKH" == "1" ]] && run_target mpcd_vkkh_play 0 "$WARMUP_STEPS" 1
fi

for rep in $(seq 1 "$REPEATS"); do
  [[ "$RUN_SRC_PERIODIC" == "1" ]] && run_target src_cuda_v2_0315m_periodic "$rep" "$STEPS" 0
  [[ "$RUN_SRC_IO" == "1" ]] && run_target src_cuda_v2_0315m_io "$rep" "$STEPS" 0
  [[ "$RUN_VKKH" == "1" ]] && run_target mpcd_vkkh_play "$rep" "$STEPS" 0
done

python3 scripts/summarize_gpu_phase_profile_0317d.py "$MANIFEST" "$ART_DIR"

echo "[0317d-profile] manifest: $MANIFEST"
echo "[0317d-profile] summary : $ART_DIR/gpu_phase_profile_0317d_summary.csv"
echo "[0317d-profile] SRC phase breakdown: $ART_DIR/gpu_phase_profile_0317d_src_phase_breakdown.csv"
echo "[0317d-profile] SRC CUDA resident breakdown: $ART_DIR/gpu_phase_profile_0317d_cuda_resident_breakdown.csv"
