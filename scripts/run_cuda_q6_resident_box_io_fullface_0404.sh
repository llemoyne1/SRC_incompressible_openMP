#!/usr/bin/env bash
set -euo pipefail

# 0404 -- first inlet/outlet Q6-resident step for the box family.
# Scope is intentionally narrower than open_rect_obstacle_full:
#   full-face left/right inlet/outlet, solid top/bottom walls, no obstacle mask,
#   no resampling/capacity.  The masked obstacle box remains the next step.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

truthy_0404() {
  case "${1:-0}" in
    1|true|TRUE|yes|YES|on|ON|enable|enabled) return 0 ;;
    *) return 1 ;;
  esac
}

USER_BIN_SET=0
if [[ -n "${BIN+x}" ]]; then USER_BIN_SET=1; fi

NX=${NX:-64}
NY=${NY:-64}
GAMMA=${GAMMA:-20}
STEPS=${STEPS:-2000}
SUMMARY_EVERY=${SUMMARY_EVERY:-$STEPS}
DUMP_STATE_EVERY=${DUMP_STATE_EVERY:-${DUMPS_EVERY:-$SUMMARY_EVERY}}
THREADS=${THREADS:-8}
SEED=${SEED:-1620404}
DT=${DT:-0.001}
KBT=${KBT:-0.001}
INITIAL_UX=${INITIAL_UX:-0.03}
INLET_UX=${INLET_UX:-0.08}
RAMP_END_TIME=${RAMP_END_TIME:-0.05}
FORCE_BUILD=${FORCE_BUILD:-0}
BUILD_IF_STALE=${BUILD_IF_STALE:-1}
LIVE_VIS_ENABLE=${LIVE_VIS_ENABLE:-${SRC_LIVE_VIS_ENABLE:-1}}
LIVE_VIS_RUN=${LIVE_VIS_RUN:-all}
RESAMPLING_ENABLE=${RESAMPLING_ENABLE:-false}
INACTIVE_SLOTS=${INACTIVE_SLOTS:-$((4 * NY * GAMMA))}

if truthy_0404 "$RESAMPLING_ENABLE"; then
  echo "[0404-box-io] ERROR: this script isolates SRC/Q6; RESAMPLING_ENABLE must remain false." >&2
  exit 2
fi

if truthy_0404 "$LIVE_VIS_ENABLE" && [[ "$USER_BIN_SET" == "0" ]]; then
  BIN=build/src_mpcd_base_cuda_q6_resident_0400_livevis
else
  BIN=${BIN:-build/src_mpcd_base_cuda_q6_resident_0400}
fi

needs_build=0
if truthy_0404 "$FORCE_BUILD" || [[ ! -x "$BIN" ]]; then
  needs_build=1
elif truthy_0404 "$BUILD_IF_STALE"; then
  if find src include scripts/build_src_mpcd_cuda_q6_resident_0400.sh -type f -newer "$BIN" -print -quit | grep -q .; then
    needs_build=1
  fi
fi

if [[ "$needs_build" == "1" ]]; then
  if truthy_0404 "$LIVE_VIS_ENABLE"; then
    MPCD_ENABLE_LIVE_VIS=1 OUT="$BIN" bash scripts/build_src_mpcd_cuda_q6_resident_0400.sh
  else
    OUT="$BIN" bash scripts/build_src_mpcd_cuda_q6_resident_0400.sh
  fi
fi
if [[ ! -x "$BIN" ]]; then
  echo "[0404-box-io] ERROR missing binary: $BIN" >&2
  exit 127
fi
if truthy_0404 "$LIVE_VIS_ENABLE" && [[ "$USER_BIN_SET" == "1" ]]; then
  echo "[0404-box-io] livevis requested with user BIN=$BIN; assuming it was built with MPCD_ENABLE_LIVE_VIS=1" >&2
fi

TAG="${NX}x${NY}_${STEPS}"
RUN_ROOT=${RUN_ROOT:-runs/q6_resident_0404_box_io_fullface_${TAG}}
ART_DIR=${ART_DIR:-dev_history/artifacts/q6_resident_0404_box_io_fullface_${TAG}}
STATE="$RUN_ROOT/init/box_io_fullface.smpcd"
mkdir -p "$RUN_ROOT/init" "$ART_DIR"

state_args=(--output "$STATE" --Lx 2.0 --Ly 1.0 --Nx "$NX" --Ny "$NY" --gamma "$GAMMA" --kBT "$KBT" --seed "$SEED" --flow-mode uniform --mean-ux "$INITIAL_UX")
if [[ "$INACTIVE_SLOTS" != "0" && "$INACTIVE_SLOTS" != "" ]]; then
  state_args+=(--inactive-slots "$INACTIVE_SLOTS")
fi
python3 scripts/generate_validation_state_0162.py "${state_args[@]}" >&2

write_params() {
  local out_dir=$1
  local params=$2
  local projection_enable=$3
  local projection_backend=$4
  local classic_cuda=$5
  cat > "$params" <<PARAMS
inputState = $STATE
outputDir = $out_dir

Lx = 2.0
Ly = 1.0
Nx = $NX
Ny = $NY

fluidXMin0 = 0.0
fluidXMax0 = -1.0
fluidYMin0 = 0.0
fluidYMax0 = -1.0

dt = $DT
nSteps = $STEPS

bodyAccelerationX = 0.0
bodyAccelerationY = 0.0

bcLeft = inlet
bcRight = outlet
bcBottom = solid
bcTop = solid

inletUxLeft = $INLET_UX
inletUyLeft = 0.0
inletVelocityRampEnable = true
inletVelocityRampStartTime = 0.0
inletVelocityRampEndTime = $RAMP_END_TIME
inletVelocityRampInitialFactor = 0.2
inletVelocityRampFinalFactor = 1.0
inletVelocityRampProfile = smoothstep
inletVelocitySpatialProfile = uniform
inletKBT = -1.0
inletThermalNoise = 0.0
inletInjectionMode = hard_cell_density
inletReservoirMode = hard_cell_density
inletReservoirCells = 3
inletTargetOccupancy = $GAMMA
inletHardCellVelocityMean = true
inletHardCellThermalRescale = true
inletRandomizeTangential = true
inletReinjectBackflow = true

openBoundaryOutletMode = balanced_flux
openBoundaryOutletHybridBlend = 0.0
openBoundaryOutletFeedbackGain = 0.0

projectionEnable = $projection_enable
projectionBackend = $projection_backend
projectionOperator = elliptic_fv_cg
projectionMaxIterations = 800
projectionTolerance = 1.0e-10
projectionMomentumCorrectionEnable = true
q6ProjectionStrength = 1.0
projectionImmersedSolidMaskEnable = false

immersedSolidEnable = false

srcClassicCudaModeEnable = $classic_cuda
resamplingEnable = false
closedCapacityResponseEnable = false
closedCapacityVirialKickEnable = false

rotationAngle = 2.0943951023931953
randomRotationSign = true
gridShiftEnable = true
rngSeed = $SEED

thermostatEnable = true
thermostatMode = cell_relative_rescale
thermostatEvery = 1
thermostatTargetKBT = -1.0
thermostatMinParticles = 3
kBT = $KBT

wallAccommodation = 1.0
wallVpGamma = $GAMMA
wallVpMass = 1.0
wallKBT = -1.0
wallThermalNoise = 0.0

summaryEvery = $SUMMARY_EVERY
dumpStateEvery = $DUMP_STATE_EVERY
numThreads = $THREADS
PARAMS
}

livevis_off_env=(SRC_LIVE_VIS_ENABLE=0 MPCD_LIVE_VIS_ENABLE=0)
livevis_on_env=("${livevis_off_env[@]}")
if truthy_0404 "$LIVE_VIS_ENABLE"; then
  SRC_LIVE_VIS_FIELD=${SRC_LIVE_VIS_FIELD:-${LIVE_VIS_FIELD:-ux}}
  SRC_LIVE_VIS_EVERY=${SRC_LIVE_VIS_EVERY:-${LIVE_VIS_EVERY:-5}}
  SRC_LIVE_VIS_NX=${SRC_LIVE_VIS_NX:-${LIVE_VIS_NX:-768}}
  SRC_LIVE_VIS_NY=${SRC_LIVE_VIS_NY:-${LIVE_VIS_NY:-768}}
  SRC_LIVE_VIS_CLIP=${SRC_LIVE_VIS_CLIP:-${LIVE_VIS_CLIP:--1}}
  SRC_LIVE_VIS_GAIN=${SRC_LIVE_VIS_GAIN:-${LIVE_VIS_GAIN:-1.0}}
  SRC_LIVE_VIS_SMOOTH_PASSES=${SRC_LIVE_VIS_SMOOTH_PASSES:-${LIVE_VIS_SMOOTH_PASSES:-1}}
  SRC_LIVE_VIS_COLORMAP=${SRC_LIVE_VIS_COLORMAP:-${LIVE_VIS_COLORMAP:-thermal}}
  SRC_LIVE_VIS_WINDOW_SCALE=${SRC_LIVE_VIS_WINDOW_SCALE:-${LIVE_VIS_WINDOW_SCALE:-1}}
  SRC_LIVE_VIS_VSYNC=${SRC_LIVE_VIS_VSYNC:-${LIVE_VIS_VSYNC:-0}}
  SRC_LIVE_VIS_CUDA_FIELD=${SRC_LIVE_VIS_CUDA_FIELD:-${LIVE_VIS_CUDA_FIELD:-1}}
  SRC_LIVE_VIS_CUDA_SNAPSHOT=${SRC_LIVE_VIS_CUDA_SNAPSHOT:-${LIVE_VIS_CUDA_SNAPSHOT:-1}}
  SRC_LIVE_VIS_LOG_SOURCE=${SRC_LIVE_VIS_LOG_SOURCE:-${LIVE_VIS_LOG_SOURCE:-0}}
  SRC_LIVE_VIS_CONTROL_FILE=${SRC_LIVE_VIS_CONTROL_FILE:-${LIVE_VIS_CONTROL_FILE:-./livevis_control.kv}}
  SRC_LIVE_VIS_CONTROL_EVERY=${SRC_LIVE_VIS_CONTROL_EVERY:-${LIVE_VIS_CONTROL_EVERY:-1}}
  SRC_LIVE_VIS_CONTROL_LOG=${SRC_LIVE_VIS_CONTROL_LOG:-0}
  if [[ ! -f "$SRC_LIVE_VIS_CONTROL_FILE" ]]; then
    cat > "$SRC_LIVE_VIS_CONTROL_FILE" <<CONTROL
field = ${SRC_LIVE_VIS_FIELD}
clip = ${SRC_LIVE_VIS_CLIP}
gain = ${SRC_LIVE_VIS_GAIN}
smoothPasses = ${SRC_LIVE_VIS_SMOOTH_PASSES}
colormap = ${SRC_LIVE_VIS_COLORMAP}
quiverScale = ${SRC_LIVE_VIS_QUIVER_SCALE:--1}
CONTROL
  fi
  livevis_on_env=(
    SRC_LIVE_VIS_ENABLE=1 MPCD_LIVE_VIS_ENABLE=1
    SRC_LIVE_VIS_FIELD="$SRC_LIVE_VIS_FIELD"
    SRC_LIVE_VIS_EVERY="$SRC_LIVE_VIS_EVERY"
    SRC_LIVE_VIS_NX="$SRC_LIVE_VIS_NX"
    SRC_LIVE_VIS_NY="$SRC_LIVE_VIS_NY"
    SRC_LIVE_VIS_CLIP="$SRC_LIVE_VIS_CLIP"
    SRC_LIVE_VIS_GAIN="$SRC_LIVE_VIS_GAIN"
    SRC_LIVE_VIS_SMOOTH_PASSES="$SRC_LIVE_VIS_SMOOTH_PASSES"
    SRC_LIVE_VIS_COLORMAP="$SRC_LIVE_VIS_COLORMAP"
    SRC_LIVE_VIS_WINDOW_SCALE="$SRC_LIVE_VIS_WINDOW_SCALE"
    SRC_LIVE_VIS_VSYNC="$SRC_LIVE_VIS_VSYNC"
    SRC_LIVE_VIS_CUDA_FIELD="$SRC_LIVE_VIS_CUDA_FIELD"
    SRC_LIVE_VIS_CUDA_SNAPSHOT="$SRC_LIVE_VIS_CUDA_SNAPSHOT"
    SRC_LIVE_VIS_LOG_SOURCE="$SRC_LIVE_VIS_LOG_SOURCE"
    SRC_LIVE_VIS_CONTROL_FILE="$SRC_LIVE_VIS_CONTROL_FILE"
    SRC_LIVE_VIS_CONTROL_EVERY="$SRC_LIVE_VIS_CONTROL_EVERY"
    SRC_LIVE_VIS_CONTROL_LOG="$SRC_LIVE_VIS_CONTROL_LOG"
  )
fi

run_case() {
  local name=$1
  local projection_enable=$2
  local projection_backend=$3
  local classic_cuda=$4
  local livevis_key=$5
  local out_dir="$RUN_ROOT/$name"
  local params="$RUN_ROOT/params_${name}.kv"
  mkdir -p "$out_dir"
  write_params "$out_dir" "$params" "$projection_enable" "$projection_backend" "$classic_cuda"
  local livevis_env=("${livevis_off_env[@]}")
  if truthy_0404 "$LIVE_VIS_ENABLE"; then
    case "$LIVE_VIS_RUN" in
      "$livevis_key"|all) livevis_env=("${livevis_on_env[@]}") ;;
      none|off|0) ;;
    esac
  fi
  local resident_io=0
  if [[ "$classic_cuda" == "true" || "$projection_backend" == "cuda" ]]; then
    resident_io=1
  fi
  local classic_thermostat=0
  if [[ "$classic_cuda" == "true" ]]; then
    classic_thermostat=1
  fi
  local cuda_q6=0
  if [[ "$projection_backend" == "cuda" ]]; then
    cuda_q6=1
  fi
  echo "[0404-box-io] running $name params=$params residentIo=$resident_io cudaQ6=$cuda_q6"
  env \
    OMP_NUM_THREADS="$THREADS" OMP_PROC_BIND=close OMP_PLACES=cores OMP_DYNAMIC=false \
    MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263="$resident_io" \
    MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263_STRICT="$resident_io" \
    MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE="$resident_io" \
    MPCD_CUDA_PERSISTENT_SRC_COLLISION_STRICT=1 \
    MPCD_CUDA_PERSISTENT_SRC_COLLISION_ACTIVE_STRICT=1 \
    MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251="$resident_io" \
    MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251_STRICT=1 \
    MPCD_CUDA_PERSISTENT_SRC_COLLISION_WALL_SIMPLE_0253=0 \
    MPCD_CUDA_PERSISTENT_SRC_COLLISION_IMMERSED_RECT_0254=0 \
    MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE="$classic_thermostat" \
    MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_STRICT=1 \
    MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_CONSUME_STRICT=1 \
    MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260="$classic_thermostat" \
    MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260_STRICT=1 \
    MPCD_CUDA_Q6_RESIDENT_SRC_IO_FULLFACE_0404="$cuda_q6" \
    MPCD_CUDA_Q6_RESIDENT_0400="$cuda_q6" \
    MPCD_CUDA_Q6_RESIDENT_STRICT_0400="$cuda_q6" \
    MPCD_CUDA_Q6_RESIDENT_THERMOSTAT_0400="$cuda_q6" \
    "${livevis_env[@]}" \
    /usr/bin/time -o "$RUN_ROOT/${name}.time" -f 'elapsed=%e user=%U sys=%S' "$BIN" "$params"
  python3 - "$out_dir/summary_runtime.csv" "$RUN_ROOT/${name}.time" "$out_dir/validation_summary_0162.csv" "$name" <<'SUMMARYPY'
import csv
import re
import sys
summary_path, time_path, out_path, run_tag = sys.argv[1:5]
with open(summary_path, newline="") as f:
    rows = list(csv.DictReader(f))
if not rows:
    raise SystemExit(f"empty summary_runtime: {summary_path}")
last = rows[-1]
elapsed = user = sy = ""
text = open(time_path).read()
m = re.search(r"elapsed=([^\\s]+) user=([^\\s]+) sys=([^\\s]+)", text)
if m:
    elapsed, user, sy = m.groups()
fieldnames = ["runTag", "case", "elapsed_s", "user_s", "sys_s"] + list(last.keys())
out = {"runTag": run_tag, "case": "box_io_fullface", "elapsed_s": elapsed, "user_s": user, "sys_s": sy}
out.update(last)
with open(out_path, "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=fieldnames)
    w.writeheader()
    w.writerow(out)
SUMMARYPY
}

run_case src_cuda_classic false cpu true src_cuda_classic
run_case src_q6_cpu true cpu false src_q6_cpu
run_case src_q6_cuda true cuda false src_q6_cuda

python3 scripts/compare_validation_mono_config_0162.py \
  --origin "$RUN_ROOT/src_q6_cpu" \
  --optimized "$RUN_ROOT/src_q6_cuda" \
  --out "$ART_DIR/src_q6_cpu_vs_src_q6_cuda.csv" \
  --summary-out "$ART_DIR/src_q6_cpu_vs_src_q6_cuda_summary.csv"

set +e
python3 scripts/compare_validation_mono_config_0162.py \
  --origin "$RUN_ROOT/src_cuda_classic" \
  --optimized "$RUN_ROOT/src_q6_cuda" \
  --out "$ART_DIR/src_cuda_classic_vs_src_q6_cuda.csv" \
  --summary-out "$ART_DIR/src_cuda_classic_vs_src_q6_cuda_summary.csv"
src_cmp_rc=$?
set -e

python3 - "$RUN_ROOT/src_q6_cuda/summary_runtime.csv" "$ART_DIR/src_q6_cuda_metrics.txt" <<'PY'
import csv, math, sys
summary, out = sys.argv[1:3]
with open(summary, newline="") as f:
    rows = list(csv.DictReader(f))
if not rows:
    raise SystemExit("empty CUDA Q6 summary")
r = rows[-1]
if int(float(r.get("q6Applied", "0"))) != 1 or int(float(r.get("q6Converged", "0"))) != 1:
    raise SystemExit("SRC+Q6 CUDA did not apply and converge")
div = float(r.get("q6DivAfterProjectedFluxRms", "nan"))
if not math.isfinite(div) or div > 1.0e-8:
    raise SystemExit(f"SRC+Q6 CUDA projected divergence too large: {div}")
lines = [
    f"q6Iterations={r.get('q6Iterations')}",
    f"q6DivBeforeRms={r.get('q6DivBeforeRms')}",
    f"q6DivAfterProjectedFluxRms={div:.17g}",
    f"q6OpenBoundaryEnabled={r.get('q6OpenBoundaryEnabled')}",
    f"q6OpenBoundaryFluxBalance={r.get('q6OpenBoundaryFluxBalance')}",
    f"Np={r.get('Np')}",
    f"meanN={r.get('meanN')}",
    f"stdN={r.get('stdN')}",
]
with open(out, "w") as f:
    f.write("\n".join(lines) + "\n")
print("[0404-box-io] " + " ".join(lines[:5]))
PY

echo "[0404-box-io] SRC+Q6 CPU vs SRC+Q6 CUDA summary: $ART_DIR/src_q6_cpu_vs_src_q6_cuda_summary.csv"
echo "[0404-box-io] SRC CUDA classic vs SRC+Q6 CUDA summary: $ART_DIR/src_cuda_classic_vs_src_q6_cuda_summary.csv (rc=$src_cmp_rc, differences expected)"
echo "[0404-box-io] metrics: $ART_DIR/src_q6_cuda_metrics.txt"
echo "[0404-box-io] dumps/root: $RUN_ROOT"
