#!/usr/bin/env bash
set -euo pipefail

# 0409 -- autonomous left-face segmented box comparison.
# Runs SRC CUDA classic, SRC+Q6 CPU, and SRC+Q6 CUDA segmented IO.
# This script targets the current resident segmented inlet/outlet subset:
# two left-face segments, one inlet and one outlet, no immersed solid; livevis is enabled by default.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

truthy_0409() { case "${1:-0}" in 1|true|TRUE|yes|YES|on|ON|enable|enabled) return 0 ;; *) return 1 ;; esac; }
USER_BIN_SET=0
if [[ -n "${BIN+x}" ]]; then USER_BIN_SET=1; fi

Lx=${Lx:-${LX:-1.0}}
Ly=${Ly:-${LY:-1.0}}
NX=${NX:-128}
NY=${NY:-128}
GAMMA=${GAMMA:-20}
STEPS=${STEPS:-2000}
SUMMARY_EVERY=${SUMMARY_EVERY:-100}
DUMP_STATE_EVERY=${DUMP_STATE_EVERY:-${DUMPS_EVERY:-100}}
THREADS=${THREADS:-8}
SEED=${SEED:-1620409}
STATE_SEED=${STATE_SEED:-$((SEED + 11))}
DT=${DT:-0.001}
KBT=${KBT:-0.001}
PARTICLE_MASS=${PARTICLE_MASS:-1.0}
INACTIVE_SLOTS=${INACTIVE_SLOTS:-$((GAMMA * NX * NY))}

UIN=${UIN:-0.08}
UOUT=${UOUT:--0.08}
SEG_IN_MIN=${SEG_IN_MIN:-0.10}
SEG_IN_MAX=${SEG_IN_MAX:-0.35}
SEG_OUT_MIN=${SEG_OUT_MIN:-0.65}
SEG_OUT_MAX=${SEG_OUT_MAX:-0.90}
OUTLET_MODE=${OUTLET_MODE:-neumann}
OUTLET_FORCED_MASS_FLUX=${OUTLET_FORCED_MASS_FLUX:-0.0}
OUTLET_FORCED_MASS_PER_STEP=${OUTLET_FORCED_MASS_PER_STEP:-0.0}
OUTLET_FORCED_PARTICLE_FLUX=${OUTLET_FORCED_PARTICLE_FLUX:-0.0}
OUTLET_FORCED_PARTICLES_PER_STEP=${OUTLET_FORCED_PARTICLES_PER_STEP:-0}
OUTLET_FORCED_LAYER_CELLS=${OUTLET_FORCED_LAYER_CELLS:-3}

ROTATION_ANGLE=${ROTATION_ANGLE:-2.0943951023931953}
RANDOM_ROTATION_SIGN=${RANDOM_ROTATION_SIGN:-true}
GRID_SHIFT_ENABLE=${GRID_SHIFT_ENABLE:-true}
PROJECTION_OPERATOR=${PROJECTION_OPERATOR:-elliptic_fv_cg}
PROJECTION_MAX_ITERATIONS=${PROJECTION_MAX_ITERATIONS:-800}
PROJECTION_TOLERANCE=${PROJECTION_TOLERANCE:-1.0e-10}
PROJECTION_MOMENTUM_CORRECTION_ENABLE=${PROJECTION_MOMENTUM_CORRECTION_ENABLE:-true}
Q6_PROJECTION_STRENGTH=${Q6_PROJECTION_STRENGTH:-1.0}
THERMOSTAT_ENABLE=${THERMOSTAT_ENABLE:-true}
THERMOSTAT_MODE=${THERMOSTAT_MODE:-cell_relative_rescale}
THERMOSTAT_EVERY=${THERMOSTAT_EVERY:-1}
THERMOSTAT_TARGET_KBT=${THERMOSTAT_TARGET_KBT:--1.0}
THERMOSTAT_MIN_PARTICLES=${THERMOSTAT_MIN_PARTICLES:-3}

FORCE_BUILD=${FORCE_BUILD:-0}
BUILD_IF_STALE=${BUILD_IF_STALE:-1}
LIVE_VIS_ENABLE=${LIVE_VIS_ENABLE:-${SRC_LIVE_VIS_ENABLE:-1}}
LIVE_VIS_RUN=${LIVE_VIS_RUN:-all}
RESAMPLING_ENABLE=${RESAMPLING_ENABLE:-false}
PARAM_OVERRIDES_FILE=${PARAM_OVERRIDES_FILE:-}
PARAM_OVERRIDES_TEXT=${PARAM_OVERRIDES_TEXT:-}

if truthy_0409 "$RESAMPLING_ENABLE"; then echo "[0409-box-segmented] ERROR: RESAMPLING_ENABLE must remain false." >&2; exit 2; fi
if truthy_0409 "$LIVE_VIS_ENABLE" && [[ "$USER_BIN_SET" == "0" ]]; then BIN=build/src_mpcd_base_cuda_q6_resident_0400_livevis; else BIN=${BIN:-build/src_mpcd_base_cuda_q6_resident_0400}; fi
needs_build=0
if truthy_0409 "$FORCE_BUILD" || [[ ! -x "$BIN" ]]; then needs_build=1; elif truthy_0409 "$BUILD_IF_STALE"; then if find src include scripts/build_src_mpcd_cuda_q6_resident_0400.sh -type f -newer "$BIN" -print -quit | grep -q .; then needs_build=1; fi; fi
if [[ "$needs_build" == "1" ]]; then if truthy_0409 "$LIVE_VIS_ENABLE"; then MPCD_ENABLE_LIVE_VIS=1 OUT="$BIN" bash scripts/build_src_mpcd_cuda_q6_resident_0400.sh; else OUT="$BIN" bash scripts/build_src_mpcd_cuda_q6_resident_0400.sh; fi; fi
if [[ ! -x "$BIN" ]]; then echo "[0409-box-segmented] ERROR missing binary: $BIN" >&2; exit 127; fi

TAG="${NX}x${NY}_${STEPS}_uin${UIN}_uout${UOUT}"
RUN_ROOT=${RUN_ROOT:-runs/q6_resident_0409_box_segmented_autonomous_${TAG}}
ART_DIR=${ART_DIR:-dev_history/artifacts/q6_resident_0409_box_segmented_autonomous_${TAG}}
STATE="$RUN_ROOT/init/box_segmented.smpcd"
mkdir -p "$RUN_ROOT/init" "$ART_DIR"

state_args=(--output "$STATE" --Lx "$Lx" --Ly "$Ly" --Nx "$NX" --Ny "$NY" --gamma "$GAMMA" --kBT "$KBT" --mass "$PARTICLE_MASS" --seed "$STATE_SEED" --flow-mode zero --mean-ux 0.0 --mean-uy 0.0 --flow-amplitude 0.0)
if [[ "$INACTIVE_SLOTS" != "0" && "$INACTIVE_SLOTS" != "" ]]; then state_args+=(--inactive-slots "$INACTIVE_SLOTS"); fi
python3 scripts/generate_validation_state_0162.py "${state_args[@]}" >&2

append_param_overrides_0409() {
  local params=$1
  if [[ -n "$PARAM_OVERRIDES_FILE" ]]; then { printf '\n# PARAM_OVERRIDES_FILE: %s\n' "$PARAM_OVERRIDES_FILE"; cat "$PARAM_OVERRIDES_FILE"; printf '\n'; } >> "$params"; fi
  if [[ -n "$PARAM_OVERRIDES_TEXT" ]]; then { printf '\n# PARAM_OVERRIDES_TEXT\n'; printf '%s\n' "$PARAM_OVERRIDES_TEXT"; } >> "$params"; fi
}

write_params_0409() {
  local out_dir=$1 params=$2 projection_enable=$3 projection_backend=$4 classic_cuda=$5
  cat > "$params" <<PARAMS
inputState = $STATE
outputDir = $out_dir

Lx = $Lx
Ly = $Ly
Nx = $NX
Ny = $NY

dt = $DT
nSteps = $STEPS

bcLeft = solid
bcRight = solid
bcBottom = solid
bcTop = solid
bcX = solid
bcY = solid

openBoundarySegmentsEnable = true
openBoundarySegmentCount = 2
openBoundarySegment0 = left inlet $SEG_IN_MIN $SEG_IN_MAX $UIN 0.0 0 $PARTICLE_MASS
openBoundarySegment1 = left outlet $SEG_OUT_MIN $SEG_OUT_MAX $UOUT 0.0 0 $PARTICLE_MASS

inletVelocityRampEnable = true
inletVelocityRampStartTime = 0.0
inletVelocityRampEndTime = 0.25
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

openBoundaryOutletMode = $OUTLET_MODE
openBoundaryOutletHybridBlend = 0.0
openBoundaryOutletFeedbackGain = 0.0
openBoundaryOutletForcedMassFlux = $OUTLET_FORCED_MASS_FLUX
openBoundaryOutletForcedMassPerStep = $OUTLET_FORCED_MASS_PER_STEP
openBoundaryOutletForcedParticleFlux = $OUTLET_FORCED_PARTICLE_FLUX
openBoundaryOutletForcedParticlesPerStep = $OUTLET_FORCED_PARTICLES_PER_STEP
openBoundaryOutletForcedLayerCells = $OUTLET_FORCED_LAYER_CELLS

wallAccommodation = 1.0
wallVpGamma = $GAMMA
wallVpMass = $PARTICLE_MASS
wallKBT = -1.0
wallThermalNoise = 0.0

projectionEnable = $projection_enable
projectionBackend = $projection_backend
projectionOperator = $PROJECTION_OPERATOR
projectionMaxIterations = $PROJECTION_MAX_ITERATIONS
projectionTolerance = $PROJECTION_TOLERANCE
projectionMomentumCorrectionEnable = $PROJECTION_MOMENTUM_CORRECTION_ENABLE
q6ProjectionStrength = $Q6_PROJECTION_STRENGTH
projectionImmersedSolidMaskEnable = false

srcClassicCudaModeEnable = $classic_cuda
resamplingEnable = false
closedCapacityResponseEnable = false
closedCapacityVirialKickEnable = false

rotationAngle = $ROTATION_ANGLE
randomRotationSign = $RANDOM_ROTATION_SIGN
gridShiftEnable = $GRID_SHIFT_ENABLE
rngSeed = $SEED

thermostatEnable = $THERMOSTAT_ENABLE
thermostatMode = $THERMOSTAT_MODE
thermostatEvery = $THERMOSTAT_EVERY
thermostatTargetKBT = $THERMOSTAT_TARGET_KBT
thermostatMinParticles = $THERMOSTAT_MIN_PARTICLES
kBT = $KBT

summaryEvery = $SUMMARY_EVERY
dumpStateEvery = $DUMP_STATE_EVERY
numThreads = $THREADS
PARAMS
  append_param_overrides_0409 "$params"
}

livevis_off_env=(SRC_LIVE_VIS_ENABLE=0 MPCD_LIVE_VIS_ENABLE=0)
livevis_on_env=("${livevis_off_env[@]}")
if truthy_0409 "$LIVE_VIS_ENABLE"; then
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
  livevis_on_env=(SRC_LIVE_VIS_ENABLE=1 MPCD_LIVE_VIS_ENABLE=1 SRC_LIVE_VIS_FIELD="$SRC_LIVE_VIS_FIELD" SRC_LIVE_VIS_EVERY="$SRC_LIVE_VIS_EVERY" SRC_LIVE_VIS_NX="$SRC_LIVE_VIS_NX" SRC_LIVE_VIS_NY="$SRC_LIVE_VIS_NY" SRC_LIVE_VIS_CLIP="$SRC_LIVE_VIS_CLIP" SRC_LIVE_VIS_GAIN="$SRC_LIVE_VIS_GAIN" SRC_LIVE_VIS_SMOOTH_PASSES="$SRC_LIVE_VIS_SMOOTH_PASSES" SRC_LIVE_VIS_COLORMAP="$SRC_LIVE_VIS_COLORMAP" SRC_LIVE_VIS_WINDOW_SCALE="$SRC_LIVE_VIS_WINDOW_SCALE" SRC_LIVE_VIS_VSYNC="$SRC_LIVE_VIS_VSYNC" SRC_LIVE_VIS_CUDA_FIELD="$SRC_LIVE_VIS_CUDA_FIELD" SRC_LIVE_VIS_CUDA_SNAPSHOT="$SRC_LIVE_VIS_CUDA_SNAPSHOT" SRC_LIVE_VIS_LOG_SOURCE="$SRC_LIVE_VIS_LOG_SOURCE" SRC_LIVE_VIS_CONTROL_FILE="$SRC_LIVE_VIS_CONTROL_FILE" SRC_LIVE_VIS_CONTROL_EVERY="$SRC_LIVE_VIS_CONTROL_EVERY" SRC_LIVE_VIS_CONTROL_LOG="$SRC_LIVE_VIS_CONTROL_LOG")
  echo "[0409-box-segmented] livevis run=$LIVE_VIS_RUN control=$SRC_LIVE_VIS_CONTROL_FILE field=$SRC_LIVE_VIS_FIELD size=${SRC_LIVE_VIS_NX}x${SRC_LIVE_VIS_NY} scale=${SRC_LIVE_VIS_WINDOW_SCALE}"
fi

write_validation_summary_0409() {
  local out_dir=$1 name=$2
  python3 - "$out_dir/summary_runtime.csv" "$RUN_ROOT/${name}.time" "$out_dir/validation_summary_0162.csv" "$name" <<'SUMMARYPY'
import csv, re, sys
summary_path, time_path, out_path, run_tag = sys.argv[1:5]
with open(summary_path, newline="") as f: rows = list(csv.DictReader(f))
if not rows: raise SystemExit(f"empty summary_runtime: {summary_path}")
last = rows[-1]
text = open(time_path).read() if __import__('os').path.exists(time_path) else ""
m = re.search(r"elapsed=([^\s]+) user=([^\s]+) sys=([^\s]+)", text)
elapsed, user, sy = m.groups() if m else ("", "", "")
fieldnames = ["runTag", "case", "elapsed_s", "user_s", "sys_s"] + list(last.keys())
out = {"runTag": run_tag, "case": "box_segmented_same_face", "elapsed_s": elapsed, "user_s": user, "sys_s": sy}; out.update(last)
with open(out_path, "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=fieldnames); w.writeheader(); w.writerow(out)
SUMMARYPY
}

run_case_0409() {
  local name=$1 projection_enable=$2 projection_backend=$3 classic_cuda=$4 livevis_key=$5
  local out_dir="$RUN_ROOT/$name" params="$RUN_ROOT/params_${name}.kv"
  mkdir -p "$out_dir"; write_params_0409 "$out_dir" "$params" "$projection_enable" "$projection_backend" "$classic_cuda"
  local livevis_env=("${livevis_off_env[@]}")
  if truthy_0409 "$LIVE_VIS_ENABLE"; then case "$LIVE_VIS_RUN" in "$livevis_key"|all) livevis_env=("${livevis_on_env[@]}") ;; none|off|0) ;; esac; fi
  local resident_io=0 resident_q6=0 classic_thermostat=0
  if [[ "$classic_cuda" == "true" ]]; then resident_io=1; classic_thermostat=1; fi
  if [[ "$projection_backend" == "cuda" ]]; then resident_io=1; resident_q6=1; fi
  echo "[0409-box-segmented] running $name params=$params segments=left:in[$SEG_IN_MIN,$SEG_IN_MAX]/out[$SEG_OUT_MIN,$SEG_OUT_MAX]"
  env OMP_NUM_THREADS="$THREADS" OMP_PROC_BIND=close OMP_PLACES=cores OMP_DYNAMIC=false \
    MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264="$resident_io" \
    MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264_STRICT="$resident_io" \
    MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE="$resident_io" \
    MPCD_CUDA_PERSISTENT_SRC_COLLISION_MINIMAL_DOWNLOAD_0257=1 \
    MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251="$resident_io" \
    MPCD_CUDA_PERSISTENT_SRC_COLLISION_STRICT=1 \
    MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251_STRICT=1 \
    MPCD_CUDA_PERSISTENT_SRC_COLLISION_ACTIVE_STRICT=1 \
    MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE="$classic_thermostat" \
    MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_STRICT=1 \
    MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_CONSUME_STRICT=1 \
    MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260="$classic_thermostat" \
    MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260_STRICT=1 \
    MPCD_CUDA_Q6_RESIDENT_SRC_IO_SEGMENTED_0409="$resident_q6" \
    MPCD_CUDA_Q6_RESIDENT_0400="$resident_q6" \
    MPCD_CUDA_Q6_RESIDENT_STRICT_0400="$resident_q6" \
    MPCD_CUDA_Q6_RESIDENT_THERMOSTAT_0400="$resident_q6" \
    "${livevis_env[@]}" /usr/bin/time -o "$RUN_ROOT/${name}.time" -f 'elapsed=%e user=%U sys=%S' "$BIN" "$params"
  write_validation_summary_0409 "$out_dir" "$name"
}

run_case_0409 src_cuda_classic false cpu true src_cuda_classic
run_case_0409 src_q6_cpu true cpu false src_q6_cpu
run_case_0409 src_q6_cuda true cuda false src_q6_cuda

set +e
python3 scripts/compare_validation_mono_config_0162.py --origin "$RUN_ROOT/src_q6_cpu" --optimized "$RUN_ROOT/src_q6_cuda" --out "$ART_DIR/src_q6_cpu_vs_src_q6_cuda.csv" --summary-out "$ART_DIR/src_q6_cpu_vs_src_q6_cuda_summary.csv"
cpu_cmp_rc=$?
python3 scripts/compare_validation_mono_config_0162.py --origin "$RUN_ROOT/src_cuda_classic" --optimized "$RUN_ROOT/src_q6_cuda" --out "$ART_DIR/src_cuda_classic_vs_src_q6_cuda.csv" --summary-out "$ART_DIR/src_cuda_classic_vs_src_q6_cuda_summary.csv"
src_cmp_rc=$?
set -e
python3 - "$RUN_ROOT/src_cuda_classic/summary_runtime.csv" "$RUN_ROOT/src_q6_cpu/summary_runtime.csv" "$RUN_ROOT/src_q6_cuda/summary_runtime.csv" "$ART_DIR/src_modes_metrics.csv" <<'METRICPY'
import csv, math, sys
classic_path, cpu_path, cuda_path, out_path = sys.argv[1:5]
def last(path):
    with open(path, newline="") as f: rows = list(csv.DictReader(f))
    if not rows: raise SystemExit(f"empty summary: {path}")
    return rows[-1]
classic = last(classic_path); cpu = last(cpu_path); cuda = last(cuda_path)
if int(float(classic.get("q6Applied", "1"))) != 0: raise SystemExit("SRC CUDA classic unexpectedly applied Q6")
if int(float(cpu.get("q6Applied", "0"))) != 1 or int(float(cpu.get("q6Converged", "0"))) != 1: raise SystemExit("SRC+Q6 CPU did not apply and converge")
if int(float(cuda.get("q6Applied", "0"))) != 1 or int(float(cuda.get("q6Converged", "0"))) != 1: raise SystemExit("SRC+Q6 CUDA did not apply and converge")
div = float(cuda.get("q6DivAfterProjectedFluxRms", "nan"))
if not math.isfinite(div) or div > 1.0e-8: raise SystemExit(f"SRC+Q6 CUDA projected divergence too large: {div}")
metrics = ["Np", "minN", "maxN", "meanN", "stdN", "meanVx", "meanVy", "meanKinetic", "kBTEstimate", "q6Applied", "q6Converged", "q6Iterations", "q6DivBeforeRms", "q6DivAfterProjectedFluxRms", "q6CorrectionVelocityRms", "wallTime"]
with open(out_path, "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=["metric", "src_cuda_classic", "src_q6_cpu", "src_q6_cuda", "delta_cuda_minus_cpu"]); w.writeheader()
    for m in metrics:
        a, b, c = classic.get(m, ""), cpu.get(m, ""), cuda.get(m, "")
        delta = ""
        try: delta = f"{float(c) - float(b):.17g}"
        except Exception: pass
        w.writerow({"metric": m, "src_cuda_classic": a, "src_q6_cpu": b, "src_q6_cuda": c, "delta_cuda_minus_cpu": delta})
print(f"[0409-box-segmented] q6CPU it={cpu.get('q6Iterations')} q6CUDA it={cuda.get('q6Iterations')} q6CUDA divAfter={div:.6e} meanVx classic/cpu/cuda={classic.get('meanVx')}/{cpu.get('meanVx')}/{cuda.get('meanVx')}")
METRICPY

echo "[0409-box-segmented] SRC+Q6 CPU vs SRC+Q6 CUDA summary: $ART_DIR/src_q6_cpu_vs_src_q6_cuda_summary.csv (rc=$cpu_cmp_rc)"
echo "[0409-box-segmented] SRC CUDA classic vs SRC+Q6 CUDA summary: $ART_DIR/src_cuda_classic_vs_src_q6_cuda_summary.csv (rc=$src_cmp_rc, differences expected)"
echo "[0409-box-segmented] selected metrics: $ART_DIR/src_modes_metrics.csv"
echo "[0409-box-segmented] dumps/root: $RUN_ROOT"
