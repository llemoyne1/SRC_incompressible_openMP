#!/usr/bin/env bash
set -euo pipefail

# 0425 -- comparison launcher for backward-step solid vs Darcy/chi retained model.
#
# It launches, sequentially:
#   1. the attached/portable solid backward-step script in classic mode;
#   2. the autonomous Darcy/chi backward-step script with mean_outward_bath + chiVP.
#
# Default parameters are synchronized with the uploaded solid script:
#   Lx=2.0 Ly=1.0 Nx=128 Ny=96 gamma=20
#   step rectangle x=[0,1.05], y=[0,0.42]
#   UIN=0.9, UINIT=0, kBT=1, dt=0.0005, nSteps=50000
#
# For a short smoke test:
#   STEPS=1000 LIVE_VIS_HOLD_ON_EXIT=0 bash scripts/run_backward_step_solid_vs_darcy_0425.sh
#
# For the full comparison:
#   LIVE_VIS_HOLD_ON_EXIT=0 bash scripts/run_backward_step_solid_vs_darcy_0425.sh

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

truthy_0425() { case "${1:-0}" in 1|true|TRUE|yes|YES|on|ON|enable|enabled) return 0 ;; *) return 1 ;; esac; }

SOLID_SCRIPT=${SOLID_SCRIPT:-scripts/run_portable_backward_step_resampling_0337_livevis.sh}
DARCY_SCRIPT=${DARCY_SCRIPT:-scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh}

if [[ ! -f "$SOLID_SCRIPT" ]]; then
  echo "[step-compare0425] ERROR: missing solid script: $SOLID_SCRIPT" >&2
  echo "[step-compare0425] Copy the uploaded script to scripts/run_portable_backward_step_resampling_0337_livevis.sh or set SOLID_SCRIPT=..." >&2
  exit 2
fi
if [[ ! -f "$DARCY_SCRIPT" ]]; then
  echo "[step-compare0425] ERROR: missing Darcy script: $DARCY_SCRIPT" >&2
  exit 2
fi

SUITE_ROOT=${SUITE_ROOT:-runs/backward_step_solid_vs_darcy_0425}
MANIFEST=$SUITE_ROOT/backward_step_compare_manifest_0425.csv
mkdir -p "$SUITE_ROOT"

BIN=${BIN:-build/src_mpcd_base_cuda_q6_resident_0400_livevis}
FORCE_BUILD=${FORCE_BUILD:-0}
BUILD_IF_STALE=${BUILD_IF_STALE:-1}

if truthy_0425 "$FORCE_BUILD" || [[ ! -x "$BIN" ]]; then
  MPCD_ENABLE_LIVE_VIS=1 OUT="$BIN" bash scripts/build_src_mpcd_cuda_q6_resident_0400.sh
elif truthy_0425 "$BUILD_IF_STALE"; then
  if find src include scripts/build_src_mpcd_cuda_q6_resident_0400.sh -type f -newer "$BIN" -print -quit | grep -q .; then
    MPCD_ENABLE_LIVE_VIS=1 OUT="$BIN" bash scripts/build_src_mpcd_cuda_q6_resident_0400.sh
  fi
fi

if [[ ! -x "$BIN" ]]; then
  echo "[step-compare0425] ERROR missing binary: $BIN" >&2
  exit 127
fi

Lx=${Lx:-${LX:-2.0}}
Ly=${Ly:-${LY:-1.0}}
NX=${NX:-960}
NY=${NY:-480}
GAMMA=${GAMMA:-7}
STEPS=${STEPS:-5000}
DT=${DT:-0.0005}
KBT=${KBT:-0.05}
SEED=${SEED:-1628304}
THREADS=${THREADS:-8}
UIN=${UIN:-0.25}
UINIT=${UINIT:-0.25}
INACTIVE_SLOTS=${INACTIVE_SLOTS:-120000}

STEP_XMIN=${STEP_XMIN:-0.0}
STEP_XMAX=${STEP_XMAX:-1.0}
STEP_YMIN=${STEP_YMIN:-0.0}
STEP_YMAX=${STEP_YMAX:-0.52}
OUTLET_MODE=${OUTLET_MODE:-hybrid}

SUMMARY_EVERY=${SUMMARY_EVERY:-100}
DUMP_STATE_EVERY=${DUMP_STATE_EVERY:-1000}
DUMP_ROLE_FILTER=${DUMP_ROLE_FILTER:-fluid}
SUMMARY_ROLE_FILTER=${SUMMARY_ROLE_FILTER:-fluid}

LIVE_VIS_ENABLE=${LIVE_VIS_ENABLE:-1}
LIVE_VIS_HOLD_ON_EXIT=${LIVE_VIS_HOLD_ON_EXIT:-0}
LIVE_VIS_FIELD=${LIVE_VIS_FIELD:-Ux}
LIVE_VIS_EVERY=${LIVE_VIS_EVERY:-25}
LIVE_VIS_NX=${LIVE_VIS_NX:-600}
LIVE_VIS_NY=${LIVE_VIS_NY:-300}
LIVE_VIS_CLIP=${LIVE_VIS_CLIP:--1}
LIVE_VIS_GAIN=${LIVE_VIS_GAIN:-1.0}
LIVE_VIS_SMOOTH_PASSES=${LIVE_VIS_SMOOTH_PASSES:-50}
LIVE_VIS_COLORMAP=${LIVE_VIS_COLORMAP:-blue_red}
LIVE_VIS_WINDOW_SCALE=${LIVE_VIS_WINDOW_SCALE:-1}
LIVE_VIS_VSYNC=${LIVE_VIS_VSYNC:-0}
LIVE_VIS_CONTROL_FILE=${LIVE_VIS_CONTROL_FILE:-./livevis_control.kv}

DARCY_INITIAL_DEACTIVATE_BELOW_CHI=${DARCY_INITIAL_DEACTIVATE_BELOW_CHI:-0.05}
DARCY_BRINKMAN_FORCING_MODE=${DARCY_BRINKMAN_FORCING_MODE:-mean_outward_bath}
DARCY_CHI_COLLISION_VP_STRENGTH=${DARCY_CHI_COLLISION_VP_STRENGTH:-0.25}
ALPHA=${ALPHA:-800000.0}

cat > "$MANIFEST" <<CSV
mode,runRoot,outputDir,params,summary,dumpFinal,timeFile
CSV

echo "[step-compare0425] suiteRoot=$SUITE_ROOT"
echo "[step-compare0425] manifest=$MANIFEST"
echo "[step-compare0425] bin=$BIN"
echo "[step-compare0425] solidScript=$SOLID_SCRIPT"
echo "[step-compare0425] darcyScript=$DARCY_SCRIPT"
echo "[step-compare0425] steps=$STEPS dt=$DT UIN=$UIN kBT=$KBT"
echo "[step-compare0425] livevis hold=$LIVE_VIS_HOLD_ON_EXIT"

# --- Solid reference, classic mode only for apples-to-apples comparison.
SOLID_ROOT="$SUITE_ROOT/solid"
echo
echo "[step-compare0425] =================================================="
echo "[step-compare0425] running solid classic reference"
echo "[step-compare0425] =================================================="

BIN="$BIN" AUTO_BUILD=0 FORCE_REBUILD=0 \
RUN_MODES=classic BASE_RUN_ROOT="$SOLID_ROOT" CLEAN_RUN_ROOT=1 \
Lx="$Lx" Ly="$Ly" NX="$NX" NY="$NY" GAMMA="$GAMMA" \
STEPS="$STEPS" DT="$DT" KBT="$KBT" SEED="$SEED" THREADS="$THREADS" \
UIN="$UIN" UINIT="$UINIT" INACTIVE_SLOTS="$INACTIVE_SLOTS" \
STEP_XMIN="$STEP_XMIN" STEP_XMAX="$STEP_XMAX" STEP_YMIN="$STEP_YMIN" STEP_YMAX="$STEP_YMAX" \
OUTLET_MODE="$OUTLET_MODE" \
SUMMARY_EVERY="$SUMMARY_EVERY" DUMP_STATE_EVERY="$DUMP_STATE_EVERY" \
DUMP_ROLE_FILTER="$DUMP_ROLE_FILTER" SUMMARY_ROLE_FILTER="$SUMMARY_ROLE_FILTER" \
LIVE_VIS_ENABLE="$LIVE_VIS_ENABLE" LIVE_VIS_FIELD="$LIVE_VIS_FIELD" LIVE_VIS_EVERY="$LIVE_VIS_EVERY" \
LIVE_VIS_NX="$LIVE_VIS_NX" LIVE_VIS_NY="$LIVE_VIS_NY" LIVE_VIS_CLIP="$LIVE_VIS_CLIP" \
LIVE_VIS_GAIN="$LIVE_VIS_GAIN" LIVE_VIS_SMOOTH_PASSES="$LIVE_VIS_SMOOTH_PASSES" \
LIVE_VIS_COLORMAP="$LIVE_VIS_COLORMAP" LIVE_VIS_WINDOW_SCALE="$LIVE_VIS_WINDOW_SCALE" LIVE_VIS_VSYNC="$LIVE_VIS_VSYNC" \
SRC_LIVE_VIS_HOLD_ON_EXIT="$LIVE_VIS_HOLD_ON_EXIT" \
bash "$SOLID_SCRIPT"

solidOut="$SOLID_ROOT/classic/output"
solidParams="$SOLID_ROOT/classic/params/backward_step_0315.kv"
solidSummary="$solidOut/summary_runtime.csv"
solidDump="$solidOut/state_step_$(printf '%08d' "$STEPS").smpcd"
solidTime="$SOLID_ROOT/classic/logs/backward_step_0315.time"
echo "solid,$SOLID_ROOT/classic,$solidOut,$solidParams,$solidSummary,$solidDump,$solidTime" >> "$MANIFEST"

# --- Darcy retained model.
DARCY_ROOT="$SUITE_ROOT/darcy_mean_outward_chiVP_s025"
echo
echo "[step-compare0425] =================================================="
echo "[step-compare0425] running Darcy retained model"
echo "[step-compare0425] =================================================="

BIN="$BIN" FORCE_BUILD=0 BUILD_IF_STALE=0 \
RUN_ROOT="$DARCY_ROOT" TAG="backward_step_darcy_mean_outward_chiVP_s025_0425" \
Lx="$Lx" Ly="$Ly" NX="$NX" NY="$NY" GAMMA="$GAMMA" \
STEPS="$STEPS" DT="$DT" KBT="$KBT" SEED="$SEED" THREADS="$THREADS" \
UIN="$UIN" UINIT="$UINIT" INACTIVE_SLOTS="$INACTIVE_SLOTS" \
STEP_XMIN="$STEP_XMIN" STEP_XMAX="$STEP_XMAX" STEP_YMIN="$STEP_YMIN" STEP_YMAX="$STEP_YMAX" \
OUTLET_MODE="$OUTLET_MODE" \
SUMMARY_EVERY="$SUMMARY_EVERY" DUMP_STATE_EVERY="$DUMP_STATE_EVERY" \
DUMP_ROLE_FILTER="$DUMP_ROLE_FILTER" SUMMARY_ROLE_FILTER="$SUMMARY_ROLE_FILTER" \
LIVE_VIS_ENABLE="$LIVE_VIS_ENABLE" LIVE_VIS_HOLD_ON_EXIT="$LIVE_VIS_HOLD_ON_EXIT" \
LIVE_VIS_FIELD="$LIVE_VIS_FIELD" LIVE_VIS_EVERY="$LIVE_VIS_EVERY" \
LIVE_VIS_NX="$LIVE_VIS_NX" LIVE_VIS_NY="$LIVE_VIS_NY" LIVE_VIS_CLIP="$LIVE_VIS_CLIP" \
LIVE_VIS_GAIN="$LIVE_VIS_GAIN" LIVE_VIS_SMOOTH_PASSES="$LIVE_VIS_SMOOTH_PASSES" \
LIVE_VIS_COLORMAP="$LIVE_VIS_COLORMAP" LIVE_VIS_WINDOW_SCALE="$LIVE_VIS_WINDOW_SCALE" LIVE_VIS_VSYNC="$LIVE_VIS_VSYNC" \
ALPHA="$ALPHA" \
DARCY_INITIAL_DEACTIVATE_BELOW_CHI="$DARCY_INITIAL_DEACTIVATE_BELOW_CHI" \
DARCY_BRINKMAN_FORCING_MODE="$DARCY_BRINKMAN_FORCING_MODE" \
DARCY_CHI_COLLISION_VP_ENABLE=true \
DARCY_CHI_COLLISION_VP_STRENGTH="$DARCY_CHI_COLLISION_VP_STRENGTH" \
DARCY_CHI_COLLISION_VP_GAMMA=-1 \
DARCY_CHI_COLLISION_VP_LAYERS=1 \
DARCY_CHI_COLLISION_VP_THRESHOLD=0.5 \
WALL_KBT=-1.0 \
bash "$DARCY_SCRIPT"

darcyOut="$DARCY_ROOT/output"
darcyParams="$DARCY_ROOT/params/src_classic_darcy_step.kv"
darcySummary="$darcyOut/summary_runtime.csv"
darcyDump="$darcyOut/state_step_$(printf '%08d' "$STEPS").smpcd"
darcyTime="$DARCY_ROOT/logs/src_classic_darcy_step.time"
echo "darcy_mean_outward_chiVP_s025,$DARCY_ROOT,$darcyOut,$darcyParams,$darcySummary,$darcyDump,$darcyTime" >> "$MANIFEST"

echo
echo "[step-compare0425] done"
echo "[step-compare0425] manifest=$MANIFEST"
