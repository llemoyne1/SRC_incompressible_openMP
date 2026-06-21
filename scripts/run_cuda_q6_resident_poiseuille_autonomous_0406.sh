#!/usr/bin/env bash
set -euo pipefail

# 0406 -- autonomous Poiseuille comparison with explicit simulation parameters.
# Runs resident SRC classic and resident SRC/Q6 CUDA. Parameters can be changed
# by environment variables; PARAM_OVERRIDES_FILE or PARAM_OVERRIDES_TEXT can
# append arbitrary .kv keys at the end of each params file.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

truthy_0406() { case "${1:-0}" in 1|true|TRUE|yes|YES|on|ON|enable|enabled) return 0 ;; *) return 1 ;; esac; }
USER_BIN_SET=0
if [[ -n "${BIN+x}" ]]; then USER_BIN_SET=1; fi

Lx=${Lx:-${LX:-2.0}}
Ly=${Ly:-${LY:-1.0}}
NX=${NX:-128}
NY=${NY:-64}
GAMMA=${GAMMA:-20}
STEPS=${STEPS:-2000}
SUMMARY_EVERY=${SUMMARY_EVERY:-100}
DUMP_STATE_EVERY=${DUMP_STATE_EVERY:-${DUMPS_EVERY:-100}}
THREADS=${THREADS:-8}
SEED=${SEED:-1620406}
STATE_SEED=${STATE_SEED:-$((SEED + 11))}
DT=${DT:-0.001}
KBT=${KBT:-0.001}
PARTICLE_MASS=${PARTICLE_MASS:-1.0}
INITIAL_FLOW_MODE=${INITIAL_FLOW_MODE:-zero}
INITIAL_UX=${INITIAL_UX:-0.0}
INITIAL_UY=${INITIAL_UY:-0.0}
INITIAL_FLOW_AMPLITUDE=${INITIAL_FLOW_AMPLITUDE:-0.0}
INACTIVE_SLOTS=${INACTIVE_SLOTS:-0}

BODY_ACCEL_X=${BODY_ACCEL_X:-${BODY_FORCE_X:-${POIS_BODY_ACCEL:-0.1}}}
BODY_ACCEL_Y=${BODY_ACCEL_Y:-${BODY_FORCE_Y:-0.0}}
TG_FORCING_ENABLE=${TG_FORCING_ENABLE:-false}
TG_FORCING_AMPLITUDE=${TG_FORCING_AMPLITUDE:-0.0}
TG_FORCING_MODE_X=${TG_FORCING_MODE_X:-1}
TG_FORCING_MODE_Y=${TG_FORCING_MODE_Y:-1}

BC_LEFT=${BC_LEFT:-periodic}
BC_RIGHT=${BC_RIGHT:-periodic}
BC_BOTTOM=${BC_BOTTOM:-solid}
BC_TOP=${BC_TOP:-solid}
WALL_VP_ENABLE=${WALL_VP_ENABLE:-true}
WALL_ACCOMMODATION=${WALL_ACCOMMODATION:-1.0}
WALL_VP_GAMMA=${WALL_VP_GAMMA:-$GAMMA}
WALL_VP_MASS=${WALL_VP_MASS:-1.0}
WALL_KBT=${WALL_KBT:-$KBT}
WALL_THERMAL_NOISE=${WALL_THERMAL_NOISE:-0.0}
WALL_UX_BOTTOM=${WALL_UX_BOTTOM:-0.0}
WALL_UY_BOTTOM=${WALL_UY_BOTTOM:-0.0}
WALL_UX_TOP=${WALL_UX_TOP:-0.0}
WALL_UY_TOP=${WALL_UY_TOP:-0.0}
ROTATION_ANGLE=${ROTATION_ANGLE:-2.0943951023931953}
RANDOM_ROTATION_SIGN=${RANDOM_ROTATION_SIGN:-true}
GRID_SHIFT_ENABLE=${GRID_SHIFT_ENABLE:-true}
PROJECTION_OPERATOR=${PROJECTION_OPERATOR:-channel_fv_cg}
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
LIVE_VIS_RUN=${LIVE_VIS_RUN:-q6}
RESAMPLING_ENABLE=${RESAMPLING_ENABLE:-false}
PARAM_OVERRIDES_FILE=${PARAM_OVERRIDES_FILE:-}
PARAM_OVERRIDES_TEXT=${PARAM_OVERRIDES_TEXT:-}

if truthy_0406 "$RESAMPLING_ENABLE"; then echo "[0406-poiseuille-autonomous] ERROR: RESAMPLING_ENABLE must remain false." >&2; exit 2; fi
if truthy_0406 "$TG_FORCING_ENABLE"; then echo "[0406-poiseuille-autonomous] WARNING: TG forcing is enabled in a wall-channel case; outside default Poiseuille validation." >&2; fi

if truthy_0406 "$LIVE_VIS_ENABLE" && [[ "$USER_BIN_SET" == "0" ]]; then BIN=build/src_mpcd_base_cuda_q6_resident_0400_livevis; else BIN=${BIN:-build/src_mpcd_base_cuda_q6_resident_0400}; fi
needs_build=0
if truthy_0406 "$FORCE_BUILD" || [[ ! -x "$BIN" ]]; then needs_build=1; elif truthy_0406 "$BUILD_IF_STALE"; then if find src include scripts/build_src_mpcd_cuda_q6_resident_0400.sh -type f -newer "$BIN" -print -quit | grep -q .; then needs_build=1; fi; fi
if [[ "$needs_build" == "1" ]]; then if truthy_0406 "$LIVE_VIS_ENABLE"; then MPCD_ENABLE_LIVE_VIS=1 OUT="$BIN" bash scripts/build_src_mpcd_cuda_q6_resident_0400.sh; else OUT="$BIN" bash scripts/build_src_mpcd_cuda_q6_resident_0400.sh; fi; fi
if [[ ! -x "$BIN" ]]; then echo "[0406-poiseuille-autonomous] ERROR missing binary: $BIN" >&2; exit 127; fi

TAG="${NX}x${NY}_${STEPS}_bf${BODY_ACCEL_X}_${BODY_ACCEL_Y}_tgf${TG_FORCING_AMPLITUDE}"
RUN_ROOT=${RUN_ROOT:-runs/q6_resident_0406_poiseuille_autonomous_${TAG}}
ART_DIR=${ART_DIR:-dev_history/artifacts/q6_resident_0406_poiseuille_autonomous_${TAG}}
STATE="$RUN_ROOT/init/poiseuille_wall.smpcd"
mkdir -p "$RUN_ROOT/init" "$ART_DIR"

state_args=(--output "$STATE" --Lx "$Lx" --Ly "$Ly" --Nx "$NX" --Ny "$NY" --gamma "$GAMMA" --kBT "$KBT" --mass "$PARTICLE_MASS" --seed "$STATE_SEED" --flow-mode "$INITIAL_FLOW_MODE" --mean-ux "$INITIAL_UX" --mean-uy "$INITIAL_UY" --flow-amplitude "$INITIAL_FLOW_AMPLITUDE")
if [[ "$INACTIVE_SLOTS" != "0" && "$INACTIVE_SLOTS" != "" ]]; then state_args+=(--inactive-slots "$INACTIVE_SLOTS"); fi
python3 scripts/generate_validation_state_0162.py "${state_args[@]}" >&2

append_param_overrides_0406() {
  local params=$1
  if [[ -n "$PARAM_OVERRIDES_FILE" ]]; then { printf '\n# PARAM_OVERRIDES_FILE: %s\n' "$PARAM_OVERRIDES_FILE"; cat "$PARAM_OVERRIDES_FILE"; printf '\n'; } >> "$params"; fi
  if [[ -n "$PARAM_OVERRIDES_TEXT" ]]; then { printf '\n# PARAM_OVERRIDES_TEXT\n'; printf '%s\n' "$PARAM_OVERRIDES_TEXT"; } >> "$params"; fi
}

write_params_0406() {
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

bodyAccelerationX = $BODY_ACCEL_X
bodyAccelerationY = $BODY_ACCEL_Y
taylorGreenForcingEnable = $TG_FORCING_ENABLE
taylorGreenForcingAmplitude = $TG_FORCING_AMPLITUDE
taylorGreenForcingModeX = $TG_FORCING_MODE_X
taylorGreenForcingModeY = $TG_FORCING_MODE_Y

bcLeft = $BC_LEFT
bcRight = $BC_RIGHT
bcBottom = $BC_BOTTOM
bcTop = $BC_TOP
bcX = periodic
bcY = solid

wallVpEnable = $WALL_VP_ENABLE
wallAccommodation = $WALL_ACCOMMODATION
wallVpGamma = $WALL_VP_GAMMA
wallVpMass = $WALL_VP_MASS
wallKBT = $WALL_KBT
wallThermalNoise = $WALL_THERMAL_NOISE
wallUxBottom = $WALL_UX_BOTTOM
wallUyBottom = $WALL_UY_BOTTOM
wallUxTop = $WALL_UX_TOP
wallUyTop = $WALL_UY_TOP

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
  append_param_overrides_0406 "$params"
}

livevis_off_env=(SRC_LIVE_VIS_ENABLE=0 MPCD_LIVE_VIS_ENABLE=0)
livevis_on_env=("${livevis_off_env[@]}")
if truthy_0406 "$LIVE_VIS_ENABLE"; then
  SRC_LIVE_VIS_FIELD=${SRC_LIVE_VIS_FIELD:-${LIVE_VIS_FIELD:-ux}}
  SRC_LIVE_VIS_EVERY=${SRC_LIVE_VIS_EVERY:-${LIVE_VIS_EVERY:-5}}
  SRC_LIVE_VIS_NX=${SRC_LIVE_VIS_NX:-${LIVE_VIS_NX:-768}}
  SRC_LIVE_VIS_NY=${SRC_LIVE_VIS_NY:-${LIVE_VIS_NY:-384}}
  SRC_LIVE_VIS_CLIP=${SRC_LIVE_VIS_CLIP:-${LIVE_VIS_CLIP:--1}}
  SRC_LIVE_VIS_GAIN=${SRC_LIVE_VIS_GAIN:-${LIVE_VIS_GAIN:-1.0}}
  SRC_LIVE_VIS_SMOOTH_PASSES=${SRC_LIVE_VIS_SMOOTH_PASSES:-${LIVE_VIS_SMOOTH_PASSES:-1}}
  SRC_LIVE_VIS_COLORMAP=${SRC_LIVE_VIS_COLORMAP:-${LIVE_VIS_COLORMAP:-thermal}}
  SRC_LIVE_VIS_WINDOW_SCALE=${SRC_LIVE_VIS_WINDOW_SCALE:-${LIVE_VIS_WINDOW_SCALE:-1}}
  SRC_LIVE_VIS_VSYNC=${SRC_LIVE_VIS_VSYNC:-${LIVE_VIS_VSYNC:-0}}
  SRC_LIVE_VIS_CUDA_FIELD=${SRC_LIVE_VIS_CUDA_FIELD:-${LIVE_VIS_CUDA_FIELD:-1}}
  SRC_LIVE_VIS_CUDA_SNAPSHOT=${SRC_LIVE_VIS_CUDA_SNAPSHOT:-${LIVE_VIS_CUDA_SNAPSHOT:-1}}
  SRC_LIVE_VIS_LOG_SOURCE=${SRC_LIVE_VIS_LOG_SOURCE:-${LIVE_VIS_LOG_SOURCE:-1}}
  SRC_LIVE_VIS_CONTROL_FILE=${SRC_LIVE_VIS_CONTROL_FILE:-${LIVE_VIS_CONTROL_FILE:-./livevis_control.kv}}
  SRC_LIVE_VIS_CONTROL_EVERY=${SRC_LIVE_VIS_CONTROL_EVERY:-${LIVE_VIS_CONTROL_EVERY:-1}}
  SRC_LIVE_VIS_CONTROL_LOG=${SRC_LIVE_VIS_CONTROL_LOG:-${LIVE_VIS_CONTROL_LOG:-1}}
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
  echo "[0406-poiseuille-autonomous] livevis run=$LIVE_VIS_RUN control=$SRC_LIVE_VIS_CONTROL_FILE field=$SRC_LIVE_VIS_FIELD size=${SRC_LIVE_VIS_NX}x${SRC_LIVE_VIS_NY} scale=${SRC_LIVE_VIS_WINDOW_SCALE}"
fi

write_validation_summary_0406() {
  local out_dir=$1 name=$2
  python3 - "$out_dir/summary_runtime.csv" "$RUN_ROOT/${name}.time" "$out_dir/validation_summary_0162.csv" "$name" <<'SUMMARYPY'
import csv, re, sys
summary_path, time_path, out_path, run_tag = sys.argv[1:5]
with open(summary_path, newline="") as f: rows = list(csv.DictReader(f))
if not rows: raise SystemExit(f"empty summary_runtime: {summary_path}")
last = rows[-1]; elapsed = user = sy = ""; text = open(time_path).read(); m = re.search(r"elapsed=([^\s]+) user=([^\s]+) sys=([^\s]+)", text)
if m: elapsed, user, sy = m.groups()
fieldnames = ["runTag", "case", "elapsed_s", "user_s", "sys_s"] + list(last.keys())
out = {"runTag": run_tag, "case": "poiseuille_wall_full", "elapsed_s": elapsed, "user_s": user, "sys_s": sy}; out.update(last)
with open(out_path, "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=fieldnames); w.writeheader(); w.writerow(out)
SUMMARYPY
}

run_case_0406() {
  local name=$1 projection_enable=$2 projection_backend=$3 classic_cuda=$4 livevis_key=$5
  local out_dir="$RUN_ROOT/$name" params="$RUN_ROOT/params_${name}.kv"
  mkdir -p "$out_dir"; write_params_0406 "$out_dir" "$params" "$projection_enable" "$projection_backend" "$classic_cuda"
  local livevis_env=("${livevis_off_env[@]}")
  if truthy_0406 "$LIVE_VIS_ENABLE"; then case "$LIVE_VIS_RUN" in "$livevis_key"|all) livevis_env=("${livevis_on_env[@]}") ;; none|off|0) ;; esac; fi
  local resident_wall=0 resident_q6=0 classic_thermostat=0
  if [[ "$classic_cuda" == "true" ]]; then resident_wall=1; classic_thermostat=1; fi
  if [[ "$projection_backend" == "cuda" ]]; then resident_wall=1; resident_q6=1; fi
  echo "[0406-poiseuille-autonomous] running $name params=$params body=($BODY_ACCEL_X,$BODY_ACCEL_Y) tgForce=$TG_FORCING_ENABLE/$TG_FORCING_AMPLITUDE"
  env OMP_NUM_THREADS="$THREADS" OMP_PROC_BIND=close OMP_PLACES=cores OMP_DYNAMIC=false MPCD_CUDA_STREAMING_WALL_SIMPLE_0246="$resident_wall" MPCD_CUDA_CLASSIC_SRC_WALL_RESIDENT_0261="$resident_wall" MPCD_CUDA_STREAMING_WALL_SIMPLE_0246_DOWNLOAD_ALL=0 MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE="$resident_wall" MPCD_CUDA_PERSISTENT_SRC_COLLISION_WALL_SIMPLE_0253="$resident_wall" MPCD_CUDA_PERSISTENT_SRC_COLLISION_STRICT=1 MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251="$resident_wall" MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251_STRICT=1 MPCD_CUDA_PERSISTENT_SRC_COLLISION_ACTIVE_STRICT=1 MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE="$classic_thermostat" MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_STRICT=1 MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_CONSUME_STRICT=1 MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260="$classic_thermostat" MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260_STRICT=1 MPCD_CUDA_Q6_RESIDENT_SRC_WALL_STEP_0402="$resident_q6" MPCD_CUDA_Q6_RESIDENT_0400="$resident_q6" MPCD_CUDA_Q6_RESIDENT_STRICT_0400="$resident_q6" MPCD_CUDA_Q6_RESIDENT_THERMOSTAT_0400="$resident_q6" "${livevis_env[@]}" /usr/bin/time -f 'elapsed=%e user=%U sys=%S' "$BIN" "$params" > "$RUN_ROOT/${name}.log" 2> "$RUN_ROOT/${name}.time"
  write_validation_summary_0406 "$out_dir" "$name"
}

run_case_0406 src false cpu true src
run_case_0406 cuda_q6 true cuda false q6

set +e
python3 scripts/compare_validation_mono_config_0162.py --origin "$RUN_ROOT/src" --optimized "$RUN_ROOT/cuda_q6" --out "$ART_DIR/src_vs_cuda_q6.csv" --summary-out "$ART_DIR/src_vs_cuda_q6_summary.csv"
compare_rc=$?
set -e
python3 - "$RUN_ROOT/src/summary_runtime.csv" "$RUN_ROOT/cuda_q6/summary_runtime.csv" "$ART_DIR/src_vs_cuda_q6_metrics.csv" <<'METRICPY'
import csv, math, sys
src_path, q6_path, out_path = sys.argv[1:4]
def last(path):
    with open(path, newline="") as f: rows = list(csv.DictReader(f))
    if not rows: raise SystemExit(f"empty summary: {path}")
    return rows[-1]
src = last(src_path); q6 = last(q6_path)
if int(float(src.get("q6Applied", "1"))) != 0: raise SystemExit("SRC run unexpectedly applied Q6")
if int(float(q6.get("q6Applied", "0"))) != 1 or int(float(q6.get("q6Converged", "0"))) != 1: raise SystemExit("CUDA Q6 did not apply and converge")
div = float(q6.get("q6DivAfterProjectedFluxRms", "nan"))
if not math.isfinite(div) or div > 1.0e-8: raise SystemExit(f"CUDA Q6 projected divergence too large: {div}")
metrics = ["Np", "minN", "maxN", "meanN", "stdN", "meanVx", "meanVy", "meanKinetic", "kBTEstimate", "q6Applied", "q6Converged", "q6Iterations", "q6DivBeforeRms", "q6DivAfterProjectedFluxRms", "q6CorrectionVelocityRms", "wallTime"]
with open(out_path, "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=["metric", "src", "cuda_q6", "delta"]); w.writeheader()
    for m in metrics:
        a, b = src.get(m, ""), q6.get(m, ""); delta = ""
        try: delta = f"{float(b) - float(a):.17g}"
        except Exception: pass
        w.writerow({"metric": m, "src": a, "cuda_q6": b, "delta": delta})
print(f"[0406-poiseuille-autonomous] q6Iterations={q6.get('q6Iterations')} q6DivAfter={div:.6e} meanVx {src.get('meanVx')} -> {q6.get('meanVx')}")
METRICPY

echo "[0406-poiseuille-autonomous] physical SRC vs CUDA-Q6 summary: $ART_DIR/src_vs_cuda_q6_summary.csv (rc=$compare_rc, differences expected)"
echo "[0406-poiseuille-autonomous] selected metrics: $ART_DIR/src_vs_cuda_q6_metrics.csv"
echo "[0406-poiseuille-autonomous] dumps/root: $RUN_ROOT"
