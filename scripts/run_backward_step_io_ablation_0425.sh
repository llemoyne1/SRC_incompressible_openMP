#!/usr/bin/env bash
set -euo pipefail

# 0425b -- backward-step IO-path ablation launcher.
#
# Runs four comparable 1000-step cases by default:
#   solid_fullface    : uploaded solid script, full-face IO + immersed rectangle
#   solid_segmented   : new solid script, segmented IO + immersed rectangle
#   darcy_segmented   : uploaded Darcy script, segmented IO + chi/Darcy
#   darcy_fullface    : new Darcy script, full-face IO + chi/Darcy
#
# Purpose:
#   isolate whether the step slowdown comes mostly from segmented IO or from
#   the Darcy/chi path itself.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

truthy_0425() { case "${1:-0}" in 1|true|TRUE|yes|YES|on|ON|enable|enabled) return 0 ;; *) return 1 ;; esac; }

SOLID_FULLFACE_SCRIPT=${SOLID_FULLFACE_SCRIPT:-scripts/run_portable_backward_step_resampling_0337_livevis.sh}
SOLID_SEGMENTED_SCRIPT=${SOLID_SEGMENTED_SCRIPT:-scripts/run_portable_backward_step_solid_segmented_0425.sh}
DARCY_SEGMENTED_SCRIPT=${DARCY_SEGMENTED_SCRIPT:-scripts/run_src_classic_cuda_darcy_chi_backward_step_0425.sh}
DARCY_FULLFACE_SCRIPT=${DARCY_FULLFACE_SCRIPT:-scripts/run_src_classic_cuda_darcy_chi_backward_step_fullface_0425.sh}

RUN_ABLATIONS=${RUN_ABLATIONS:-"solid_fullface solid_segmented darcy_segmented darcy_fullface"}
SUITE_ROOT=${SUITE_ROOT:-runs/backward_step_io_ablation_0425}
MANIFEST=$SUITE_ROOT/backward_step_io_ablation_manifest_0425.csv
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
[[ -x "$BIN" ]] || { echo "[io-ablation0425] ERROR missing binary: $BIN" >&2; exit 127; }

# Common short performance-test defaults.
Lx=${Lx:-${LX:-2.0}}
Ly=${Ly:-${LY:-1.0}}
NX=${NX:-960}
NY=${NY:-480}
GAMMA=${GAMMA:-7}
STEPS=${STEPS:-1000}
SUMMARY_EVERY=${SUMMARY_EVERY:-100}
DUMP_STATE_EVERY=${DUMP_STATE_EVERY:-1000}
THREADS=${THREADS:-8}
SEED=${SEED:-1628304}
DT=${DT:-0.0005}
KBT=${KBT:-0.05}
UIN=${UIN:-0.25}
UINIT=${UINIT:-0.25}
INACTIVE_SLOTS=${INACTIVE_SLOTS:-120000}
STEP_XMIN=${STEP_XMIN:-0.0}
STEP_XMAX=${STEP_XMAX:-1.0}
STEP_YMIN=${STEP_YMIN:-0.0}
STEP_YMAX=${STEP_YMAX:-0.52}
OUTLET_MODE=${OUTLET_MODE:-hybrid}

LIVE_VIS_ENABLE=${LIVE_VIS_ENABLE:-0}
LIVE_VIS_HOLD_ON_EXIT=${LIVE_VIS_HOLD_ON_EXIT:-0}
LIVE_VIS_FIELD=${LIVE_VIS_FIELD:-Ux}
LIVE_VIS_EVERY=${LIVE_VIS_EVERY:-25}
LIVE_VIS_NX=${LIVE_VIS_NX:-600}
LIVE_VIS_NY=${LIVE_VIS_NY:-300}
LIVE_VIS_CLIP=${LIVE_VIS_CLIP:--1}
LIVE_VIS_GAIN=${LIVE_VIS_GAIN:-1.0}
LIVE_VIS_SMOOTH_PASSES=${LIVE_VIS_SMOOTH_PASSES:-50}
LIVE_VIS_COLORMAP=${LIVE_VIS_COLORMAP:-blue_red}

DUMP_ROLE_FILTER=${DUMP_ROLE_FILTER:-fluid}
SUMMARY_ROLE_FILTER=${SUMMARY_ROLE_FILTER:-fluid}

DARCY_INITIAL_DEACTIVATE_BELOW_CHI=${DARCY_INITIAL_DEACTIVATE_BELOW_CHI:-0.05}
DARCY_BRINKMAN_FORCING_MODE=${DARCY_BRINKMAN_FORCING_MODE:-mean_outward_bath}
DARCY_CHI_COLLISION_VP_ENABLE=${DARCY_CHI_COLLISION_VP_ENABLE:-true}
DARCY_CHI_COLLISION_VP_STRENGTH=${DARCY_CHI_COLLISION_VP_STRENGTH:-0.25}
DARCY_COST_EVERY=${DARCY_COST_EVERY:-1000000}
TOPO_BENCHMARK_ENABLE=${TOPO_BENCHMARK_ENABLE:-false}
ALPHA=${ALPHA:-800000.0}

cat > "$MANIFEST" <<CSV
mode,runRoot,outputDir,params,summary,dumpFinal,timeFile
CSV

common_env=(
  BIN="$BIN" FORCE_BUILD=0 FORCE_REBUILD=0 AUTO_BUILD=0 BUILD_IF_STALE=0
  Lx="$Lx" Ly="$Ly" NX="$NX" NY="$NY" GAMMA="$GAMMA" STEPS="$STEPS"
  SUMMARY_EVERY="$SUMMARY_EVERY" DUMP_STATE_EVERY="$DUMP_STATE_EVERY"
  THREADS="$THREADS" SEED="$SEED" DT="$DT" KBT="$KBT"
  UIN="$UIN" UINIT="$UINIT" INACTIVE_SLOTS="$INACTIVE_SLOTS"
  STEP_XMIN="$STEP_XMIN" STEP_XMAX="$STEP_XMAX" STEP_YMIN="$STEP_YMIN" STEP_YMAX="$STEP_YMAX"
  OUTLET_MODE="$OUTLET_MODE"
  LIVE_VIS_ENABLE="$LIVE_VIS_ENABLE" LIVE_VIS_HOLD_ON_EXIT="$LIVE_VIS_HOLD_ON_EXIT"
  LIVE_VIS_FIELD="$LIVE_VIS_FIELD" LIVE_VIS_EVERY="$LIVE_VIS_EVERY"
  LIVE_VIS_NX="$LIVE_VIS_NX" LIVE_VIS_NY="$LIVE_VIS_NY" LIVE_VIS_CLIP="$LIVE_VIS_CLIP"
  LIVE_VIS_GAIN="$LIVE_VIS_GAIN" LIVE_VIS_SMOOTH_PASSES="$LIVE_VIS_SMOOTH_PASSES" LIVE_VIS_COLORMAP="$LIVE_VIS_COLORMAP"
  DUMP_ROLE_FILTER="$DUMP_ROLE_FILTER" SUMMARY_ROLE_FILTER="$SUMMARY_ROLE_FILTER"
)

run_solid() {
  local mode=$1 script=$2 root=$3
  echo
  echo "[io-ablation0425] running $mode"
  env "${common_env[@]}" RUN_MODES=classic BASE_RUN_ROOT="$root" CLEAN_RUN_ROOT=1 bash "$script"
  local rr="$root/classic"
  echo "$mode,$rr,$rr/output,$rr/params/backward_step_0315.kv,$rr/output/summary_runtime.csv,$rr/output/state_step_$(printf '%08d' "$STEPS").smpcd,$rr/logs/backward_step_0315.time" >> "$MANIFEST"
}

run_darcy() {
  local mode=$1 script=$2 root=$3 tag=$4
  echo
  echo "[io-ablation0425] running $mode"
  env "${common_env[@]}" \
    RUN_ROOT="$root" TAG="$tag" \
    DARCY_INITIAL_DEACTIVATE_BELOW_CHI="$DARCY_INITIAL_DEACTIVATE_BELOW_CHI" \
    DARCY_BRINKMAN_FORCING_MODE="$DARCY_BRINKMAN_FORCING_MODE" \
    DARCY_CHI_COLLISION_VP_ENABLE="$DARCY_CHI_COLLISION_VP_ENABLE" \
    DARCY_CHI_COLLISION_VP_STRENGTH="$DARCY_CHI_COLLISION_VP_STRENGTH" \
    DARCY_COST_EVERY="$DARCY_COST_EVERY" TOPO_BENCHMARK_ENABLE="$TOPO_BENCHMARK_ENABLE" ALPHA="$ALPHA" \
    bash "$script"
  echo "$mode,$root,$root/output,$root/params/src_classic_darcy_step.kv,$root/output/summary_runtime.csv,$root/output/state_step_$(printf '%08d' "$STEPS").smpcd,$root/logs/src_classic_darcy_step.time" >> "$MANIFEST"
}

echo "[io-ablation0425] suiteRoot=$SUITE_ROOT"
echo "[io-ablation0425] modes=$RUN_ABLATIONS"
echo "[io-ablation0425] steps=$STEPS grid=${NX}x${NY} gamma=$GAMMA livevis=$LIVE_VIS_ENABLE"

for mode in $RUN_ABLATIONS; do
  case "$mode" in
    solid_fullface)
      run_solid "$mode" "$SOLID_FULLFACE_SCRIPT" "$SUITE_ROOT/solid_fullface"
      ;;
    solid_segmented)
      run_solid "$mode" "$SOLID_SEGMENTED_SCRIPT" "$SUITE_ROOT/solid_segmented"
      ;;
    darcy_segmented)
      run_darcy "$mode" "$DARCY_SEGMENTED_SCRIPT" "$SUITE_ROOT/darcy_segmented" "step_darcy_segmented_io_ablation_0425"
      ;;
    darcy_fullface)
      run_darcy "$mode" "$DARCY_FULLFACE_SCRIPT" "$SUITE_ROOT/darcy_fullface" "step_darcy_fullface_io_ablation_0425"
      ;;
    *)
      echo "[io-ablation0425] ERROR unknown mode: $mode" >&2
      exit 2
      ;;
  esac
done

echo
echo "[io-ablation0425] done"
echo "[io-ablation0425] manifest=$MANIFEST"
cat "$MANIFEST"
