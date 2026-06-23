#!/usr/bin/env bash
set -euo pipefail

# 0424 -- Lightweight VP-strength sweep for the VK Darcy/chi comparison.
#
# Purpose:
#   Re-run only three additional mean_outward_bath + chiCollisionVP cases,
#   at iso-parameters with the final comparison suite, while keeping walltime limited.
#
# Default VP strengths:
#   0.25 0.50 0.75
#
# The strength=1.0 case is assumed to already exist in the final comparison run.
#
# Usage from repository root:
#   LIVE_VIS_HOLD_ON_EXIT=0 bash scripts/run_vk_vp_strength_sweep_0424.sh
#
# Optional:
#   VP_STRENGTHS="0.25 0.75 1.50" bash scripts/run_vk_vp_strength_sweep_0424.sh
#
# Outputs:
#   runs/vk_vp_strength_sweep_0424/
#   runs/vk_vp_strength_sweep_0424/vk_vp_strength_sweep_manifest_0424.csv

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

DARCY_SCRIPT="${DARCY_SCRIPT:-scripts/run_src_classic_cuda_darcy_chi_vonkarman_periodic_0416.sh}"

if [[ ! -f "$DARCY_SCRIPT" ]]; then
  echo "[vk-sweep0424] ERROR: missing Darcy VK script: $DARCY_SCRIPT" >&2
  exit 2
fi

if ! grep -q 'darcyChiCollisionVpEnable' "$DARCY_SCRIPT"; then
  echo "[vk-sweep0424] ERROR: $DARCY_SCRIPT does not appear to write darcyChiCollisionVp* keys." >&2
  echo "[vk-sweep0424] Apply darcy_vk_chivp_script_keys_0423_files_only.zip first." >&2
  exit 2
fi

truthy_0424() {
  case "${1:-0}" in
    1|true|TRUE|yes|YES|on|ON|enable|enabled) return 0 ;;
    *) return 1 ;;
  esac
}

safe_strength_0424() {
  local s="$1"
  s="${s//./p}"
  s="${s//- /m}"
  s="${s//-/m}"
  printf '%s' "$s"
}

NX="${NX:-1200}"
NY="${NY:-640}"
GAMMA="${GAMMA:-6}"
STEPS="${STEPS:-3000}"
DT="${DT:-0.0005}"
KBT="${KBT:-5.0}"
U0="${U0:-0.9}"
UINIT="${UINIT:-0.9}"
AX="${AX:-0.000005}"
AY="${AY:-0.0}"
SEED="${SEED:-1628505}"
THREADS="${THREADS:-8}"

SUMMARY_EVERY="${SUMMARY_EVERY:-300}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-1000}"
DUMP_ROLE_FILTER="${DUMP_ROLE_FILTER:-fluid}"
SUMMARY_ROLE_FILTER="${SUMMARY_ROLE_FILTER:-fluid}"

ALPHA="${ALPHA:-800000.0}"
ALPHA_MIN="${ALPHA_MIN:-0.0}"
DARCY_Q="${DARCY_Q:-0.1}"
DARCY_INITIAL_DEACTIVATE_BELOW_CHI="${DARCY_INITIAL_DEACTIVATE_BELOW_CHI:-0.05}"

DARCY_CHI_COLLISION_VP_GAMMA="${DARCY_CHI_COLLISION_VP_GAMMA:--1}"
DARCY_CHI_COLLISION_VP_LAYERS="${DARCY_CHI_COLLISION_VP_LAYERS:-1}"
DARCY_CHI_COLLISION_VP_THRESHOLD="${DARCY_CHI_COLLISION_VP_THRESHOLD:-0.5}"
DARCY_CHI_COLLISION_VP_MASS="${DARCY_CHI_COLLISION_VP_MASS:-1.0}"

VP_STRENGTHS="${VP_STRENGTHS:-0.25 0.50 0.75}"

LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-0}"
LIVE_VIS_FIELD="${LIVE_VIS_FIELD:-vorticity}"
LIVE_VIS_EVERY="${LIVE_VIS_EVERY:-10}"
LIVE_VIS_NX="${LIVE_VIS_NX:-1200}"
LIVE_VIS_NY="${LIVE_VIS_NY:-320}"
LIVE_VIS_CLIP="${LIVE_VIS_CLIP:--20}"
LIVE_VIS_GAIN="${LIVE_VIS_GAIN:-0.5}"
LIVE_VIS_SMOOTH_PASSES="${LIVE_VIS_SMOOTH_PASSES:-10}"
LIVE_VIS_COLORMAP="${LIVE_VIS_COLORMAP:-blue_red}"
LIVE_VIS_WINDOW_SCALE="${LIVE_VIS_WINDOW_SCALE:-1}"
LIVE_VIS_VSYNC="${LIVE_VIS_VSYNC:-0}"

FORCE_BUILD="${FORCE_BUILD:-0}"
BUILD_IF_STALE="${BUILD_IF_STALE:-1}"

CHI_FILE="${CHI_FILE:-./chi/chi_vonkarman_circle_xc0p2_yc0p205_rc0p04_1200x640_f32.f32}"
if [[ ! -f "$CHI_FILE" ]]; then
  echo "[vk-sweep0424] ERROR: chi file not found: $CHI_FILE" >&2
  exit 2
fi

# Prefer the solid initial state from the final comparison suite so the sweep
# remains synchronized with the iso-parameter campaign. Fall back to earlier
# solid state or to the standard Darcy init if needed.
STATE_SOURCE="${STATE_SOURCE:-}"
if [[ -z "$STATE_SOURCE" ]]; then
  CANDIDATE_FINAL_SOLID="runs/vk_final_compare_0423/solid/periodic/classic/init/von_karman_cylinder_0315_periodic_${NX}x${NY}_g${GAMMA}.smpcd"
  CANDIDATE_OLD_SOLID="runs/VK_classic_small_time/periodic/classic/init/von_karman_cylinder_0315_periodic_${NX}x${NY}_g${GAMMA}.smpcd"
  CANDIDATE_DARCY_INIT="./init/src_classic_darcy_vonkarman_U0p9_1200x640_g6_kBT5_no_circle.smpcd"
  if [[ -f "$CANDIDATE_FINAL_SOLID" ]]; then
    STATE_SOURCE="$CANDIDATE_FINAL_SOLID"
  elif [[ -f "$CANDIDATE_OLD_SOLID" ]]; then
    STATE_SOURCE="$CANDIDATE_OLD_SOLID"
  elif [[ -f "$CANDIDATE_DARCY_INIT" ]]; then
    STATE_SOURCE="$CANDIDATE_DARCY_INIT"
  else
    echo "[vk-sweep0424] ERROR: no suitable initial state found." >&2
    echo "[vk-sweep0424] Set STATE_SOURCE=/path/to/state.smpcd explicitly." >&2
    exit 2
  fi
fi

if [[ ! -f "$STATE_SOURCE" ]]; then
  echo "[vk-sweep0424] ERROR: STATE_SOURCE not found: $STATE_SOURCE" >&2
  exit 2
fi

SUITE_ROOT="${SUITE_ROOT:-runs/vk_vp_strength_sweep_0424}"
MANIFEST="$SUITE_ROOT/vk_vp_strength_sweep_manifest_0424.csv"
mkdir -p "$SUITE_ROOT"

cat > "$MANIFEST" <<CSV
mode,strength,runRoot,outputDir,params,dump1000,dump2000,dump3000,summary,topoBenchmark,timeFile
CSV

echo "[vk-sweep0424] suiteRoot=$SUITE_ROOT"
echo "[vk-sweep0424] manifest=$MANIFEST"
echo "[vk-sweep0424] stateSource=$STATE_SOURCE"
echo "[vk-sweep0424] chiFile=$CHI_FILE"
echo "[vk-sweep0424] strengths=$VP_STRENGTHS"
echo "[vk-sweep0424] livevis hold on exit=$LIVE_VIS_HOLD_ON_EXIT"

first=1
for strength in $VP_STRENGTHS; do
  safe="$(safe_strength_0424 "$strength")"
  mode="darcy_mean_outward_chiVP_strength_${safe}"
  tag="vk0424_${mode}_3000"
  run_root="$SUITE_ROOT/$mode"

  echo
  echo "[vk-sweep0424] =================================================="
  echo "[vk-sweep0424] running mode=$mode strength=$strength"
  echo "[vk-sweep0424] runRoot=$run_root"
  echo "[vk-sweep0424] =================================================="

  # Build only on the first mode unless explicitly forced.
  this_force_build="$FORCE_BUILD"
  if [[ "$first" == "0" ]]; then
    this_force_build=0
  fi

  LIVE_VIS_HOLD_ON_EXIT="$LIVE_VIS_HOLD_ON_EXIT" \
  LIVE_VIS_ENABLE="$LIVE_VIS_ENABLE" \
  LIVE_VIS_FIELD="$LIVE_VIS_FIELD" \
  LIVE_VIS_EVERY="$LIVE_VIS_EVERY" \
  LIVE_VIS_NX="$LIVE_VIS_NX" \
  LIVE_VIS_NY="$LIVE_VIS_NY" \
  LIVE_VIS_CLIP="$LIVE_VIS_CLIP" \
  LIVE_VIS_GAIN="$LIVE_VIS_GAIN" \
  LIVE_VIS_SMOOTH_PASSES="$LIVE_VIS_SMOOTH_PASSES" \
  LIVE_VIS_COLORMAP="$LIVE_VIS_COLORMAP" \
  LIVE_VIS_WINDOW_SCALE="$LIVE_VIS_WINDOW_SCALE" \
  LIVE_VIS_VSYNC="$LIVE_VIS_VSYNC" \
  NX="$NX" NY="$NY" GAMMA="$GAMMA" \
  STEPS="$STEPS" DT="$DT" KBT="$KBT" U0="$U0" UINIT="$UINIT" \
  AX="$AX" AY="$AY" SEED="$SEED" THREADS="$THREADS" \
  SUMMARY_EVERY="$SUMMARY_EVERY" DUMP_STATE_EVERY="$DUMP_STATE_EVERY" \
  DUMP_ROLE_FILTER="$DUMP_ROLE_FILTER" SUMMARY_ROLE_FILTER="$SUMMARY_ROLE_FILTER" \
  ALPHA="$ALPHA" ALPHA_MIN="$ALPHA_MIN" DARCY_Q="$DARCY_Q" \
  DARCY_INITIAL_DEACTIVATE_BELOW_CHI="$DARCY_INITIAL_DEACTIVATE_BELOW_CHI" \
  DARCY_BRINKMAN_FORCING_MODE="mean_outward_bath" \
  DARCY_CHI_COLLISION_VP_ENABLE=true \
  DARCY_CHI_COLLISION_VP_MODE=interface_band \
  DARCY_CHI_COLLISION_VP_GAMMA="$DARCY_CHI_COLLISION_VP_GAMMA" \
  DARCY_CHI_COLLISION_VP_MASS="$DARCY_CHI_COLLISION_VP_MASS" \
  DARCY_CHI_COLLISION_VP_LAYERS="$DARCY_CHI_COLLISION_VP_LAYERS" \
  DARCY_CHI_COLLISION_VP_THRESHOLD="$DARCY_CHI_COLLISION_VP_THRESHOLD" \
  DARCY_CHI_COLLISION_VP_STRENGTH="$strength" \
  CHI_FILE="$CHI_FILE" STATE_SOURCE="$STATE_SOURCE" \
  TAG="$tag" RUN_ROOT="$run_root" \
  FORCE_BUILD="$this_force_build" BUILD_IF_STALE="$BUILD_IF_STALE" \
  bash "$DARCY_SCRIPT"

  first=0

  outputDir="$run_root/output"
  params="$run_root/params/src_classic_darcy_chi.kv"
  dump1000="$outputDir/state_step_00001000.smpcd"
  dump2000="$outputDir/state_step_00002000.smpcd"
  dump3000="$outputDir/state_step_00003000.smpcd"
  summary="$outputDir/summary_runtime.csv"
  topo="$outputDir/topo_benchmark_0348.csv"
  timeFile="$run_root/logs/src_classic_darcy_chi.time"

  echo "$mode,$strength,$run_root,$outputDir,$params,$dump1000,$dump2000,$dump3000,$summary,$topo,$timeFile" >> "$MANIFEST"

  if [[ ! -f "$dump3000" ]]; then
    echo "[vk-sweep0424] WARNING: expected final dump missing: $dump3000" >&2
  fi
done

echo
echo "[vk-sweep0424] done"
echo "[vk-sweep0424] manifest=$MANIFEST"
