#!/usr/bin/env bash
set -euo pipefail

# 0307 — split-cascade diagnostics and optional prevention stress tests.
#
# This runner compares the existing local population guard against 0307 safety
# modes that prevent repeated splitting of very low-mass representative
# particles.  It is focused on the regimes where 0306 found tiny-mass/high-U
# outliers: backward step and Von Karman solid-adjacent cells.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BIN=${BIN:-build/src_mpcd_base_cuda_0307}
ART_DIR=${ART_DIR:-dev_history/artifacts/gpu_cuda_resampling_split_safety_0307}
FORCE_REBUILD=${FORCE_REBUILD:-1}
STOP_ON_FAIL=${STOP_ON_FAIL:-1}
ALLOW_DIAG_ONLY_SUCCESS=${ALLOW_DIAG_ONLY_SUCCESS:-1}
LIVE_PROGRESS=${LIVE_PROGRESS:-0}
CLEAN_RUN_ROOT=${CLEAN_RUN_ROOT:-1}
THREADS=${THREADS:-8}
GAMMA=${GAMMA:-20}
KBT=${KBT:-0.001}
SUMMARY_EVERY=${SUMMARY_EVERY:-100}
DUMP_STATE_EVERY=${DUMP_STATE_EVERY:-500}

RUN_STEP=${RUN_STEP:-1}
RUN_VK=${RUN_VK:-1}
RUN_TG_HOLE=${RUN_TG_HOLE:-0}

STEP_NX=${STEP_NX:-128}; STEP_NY=${STEP_NY:-48}; STEP_STEPS=${STEP_STEPS:-6000}; STEP_DT=${STEP_DT:-0.0008}; STEP_UIN=${STEP_UIN:-0.60}
VK_NX=${VK_NX:-128}; VK_NY=${VK_NY:-48}; VK_STEPS=${VK_STEPS:-6000}; VK_DT=${VK_DT:-0.0005}; VK_UIN=${VK_UIN:-0.45}; VK_THERMOSTAT_ENABLE=${VK_THERMOSTAT_ENABLE:-1}
TG_NX=${TG_NX:-64}; TG_NY=${TG_NY:-64}; TG_STEPS=${TG_STEPS:-2000}; TG_DT=${TG_DT:-0.001}

GUARD_NMIN=${GUARD_NMIN:-12}
GUARD_NTARGET=${GUARD_NTARGET:-20}
GUARD_NMAX=${GUARD_NMAX:-32}
GUARD_EVERY=${GUARD_EVERY:-1}
RESTORE_ENABLE=${RESTORE_ENABLE:-1}
BOUNDARY_AWARE=${BOUNDARY_AWARE:-1}
OPEN_BOUNDARY_HALO_CELLS=${OPEN_BOUNDARY_HALO_CELLS:-1}
SOLID_HALO_CELLS=${SOLID_HALO_CELLS:-0}

# Safety thresholds are intentionally explicit and can be swept externally.
DONOR_MIN_MASS=${DONOR_MIN_MASS:-0.5}
NEW_PARTICLE_MIN_MASS=${NEW_PARTICLE_MIN_MASS:-0.25}
SOLID_DONOR_MIN_MASS=${SOLID_DONOR_MIN_MASS:-1.0}
SOLID_ADJACENT_HALO_CELLS=${SOLID_ADJACENT_HALO_CELLS:-1}
TINY_MASS_THRESHOLD=${TINY_MASS_THRESHOLD:-0.25}

# Modes:
#   diag_only      : 0307 diagnostics only, no prevention; behavior should match 0299.
#   safe_floor     : donor/new-particle mass floors + prefer massive donor.
#   solid_cautious : safe_floor plus stricter donor floor near solids.
#   solid_off      : safe_floor plus split disabled in solid-adjacent cells.
SAFETY_MODES=${SAFETY_MODES:-"diag_only safe_floor solid_cautious solid_off"}

mkdir -p "$ART_DIR"
if [[ "$FORCE_REBUILD" != "0" && "$FORCE_REBUILD" != "false" && "$FORCE_REBUILD" != "FALSE" ]]; then
  OUT="$BIN" CUDA_ARCH_FLAGS="${CUDA_ARCH_FLAGS:-}" bash scripts/build_src_mpcd_cuda_0307.sh
elif [[ ! -x "$BIN" ]]; then
  OUT="$BIN" CUDA_ARCH_FLAGS="${CUDA_ARCH_FLAGS:-}" bash scripts/build_src_mpcd_cuda_0307.sh
fi

RUN_MANIFEST=${RUN_MANIFEST:-$ART_DIR/cuda_resampling_split_safety_0307_run_manifest.csv}
printf 'caseName,modeName,runRoot,exitCode,accepted,script,extraEnv\n' > "$RUN_MANIFEST"

append_manifest() {
  python3 - "$RUN_MANIFEST" "$@" <<'PY'
import csv, sys
with open(sys.argv[1], 'a', newline='') as fh:
    csv.writer(fh).writerow(sys.argv[2:])
PY
}

mode_env() {
  local mode=$1
  case "$mode" in
    diag_only)
      echo "MPCD_CUDA_RESAMPLING_SPLIT_SAFETY_0307=0 MPCD_CUDA_RESAMPLING_SPLIT_PREFER_MAX_MASS_DONOR_0307=0 MPCD_CUDA_RESAMPLING_SOLID_ADJACENT_SPLIT_MODE_0307=0"
      ;;
    safe_floor)
      echo "MPCD_CUDA_RESAMPLING_SPLIT_SAFETY_0307=1 MPCD_CUDA_RESAMPLING_SPLIT_PREFER_MAX_MASS_DONOR_0307=1 MPCD_CUDA_RESAMPLING_SPLIT_DONOR_MIN_MASS_0307=$DONOR_MIN_MASS MPCD_CUDA_RESAMPLING_SPLIT_NEW_PARTICLE_MIN_MASS_0307=$NEW_PARTICLE_MIN_MASS MPCD_CUDA_RESAMPLING_SOLID_ADJACENT_SPLIT_MODE_0307=0"
      ;;
    solid_cautious)
      echo "MPCD_CUDA_RESAMPLING_SPLIT_SAFETY_0307=1 MPCD_CUDA_RESAMPLING_SPLIT_PREFER_MAX_MASS_DONOR_0307=1 MPCD_CUDA_RESAMPLING_SPLIT_DONOR_MIN_MASS_0307=$DONOR_MIN_MASS MPCD_CUDA_RESAMPLING_SPLIT_NEW_PARTICLE_MIN_MASS_0307=$NEW_PARTICLE_MIN_MASS MPCD_CUDA_RESAMPLING_SOLID_ADJACENT_DONOR_MIN_MASS_0307=$SOLID_DONOR_MIN_MASS MPCD_CUDA_RESAMPLING_SOLID_ADJACENT_SPLIT_MODE_0307=1"
      ;;
    solid_off)
      echo "MPCD_CUDA_RESAMPLING_SPLIT_SAFETY_0307=1 MPCD_CUDA_RESAMPLING_SPLIT_PREFER_MAX_MASS_DONOR_0307=1 MPCD_CUDA_RESAMPLING_SPLIT_DONOR_MIN_MASS_0307=$DONOR_MIN_MASS MPCD_CUDA_RESAMPLING_SPLIT_NEW_PARTICLE_MIN_MASS_0307=$NEW_PARTICLE_MIN_MASS MPCD_CUDA_RESAMPLING_SOLID_ADJACENT_SPLIT_MODE_0307=2"
      ;;
    *)
      echo "[0307-split] ERROR: unknown mode '$mode'" >&2
      exit 2
      ;;
  esac
}

run_one() {
  local case_name=$1 mode=$2 script=$3 run_root=$4; shift 4
  local extra="$*"
  mkdir -p "$(dirname "$run_root")"
  local stdout_log="${run_root}.stdout.log"
  local stderr_log="${run_root}.stderr.log"
  echo "[0307-split] running case=$case_name mode=$mode script=$script"

  local safety_env
  safety_env=$(mode_env "$mode")
  local rc=0
  set +e
  env \
    BIN="$BIN" AUTO_BUILD=0 LIVE_PROGRESS="$LIVE_PROGRESS" CLEAN_RUN_ROOT="$CLEAN_RUN_ROOT" THREADS="$THREADS" \
    GAMMA="$GAMMA" KBT="$KBT" SUMMARY_EVERY="$SUMMARY_EVERY" DUMP_STATE_EVERY="$DUMP_STATE_EVERY" \
    RESAMPLING_ENABLE=1 \
    GUARD_NMIN="$GUARD_NMIN" GUARD_NTARGET="$GUARD_NTARGET" GUARD_NMAX="$GUARD_NMAX" GUARD_EVERY="$GUARD_EVERY" \
    RESTORE_ENABLE="$RESTORE_ENABLE" BOUNDARY_AWARE="$BOUNDARY_AWARE" OPEN_BOUNDARY_HALO_CELLS="$OPEN_BOUNDARY_HALO_CELLS" \
    MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297=1 \
    MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_EVERY="$GUARD_EVERY" \
    MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_NMIN="$GUARD_NMIN" \
    MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_NTARGET="$GUARD_NTARGET" \
    MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_NMAX="$GUARD_NMAX" \
    MPCD_CUDA_RESAMPLING_MOMENT_RESTORE_0298="$RESTORE_ENABLE" \
    MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0299_BOUNDARY_AWARE="$BOUNDARY_AWARE" \
    MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0299_OPEN_BOUNDARY_HALO_CELLS="$OPEN_BOUNDARY_HALO_CELLS" \
    MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0299_SOLID_HALO_CELLS="$SOLID_HALO_CELLS" \
    MPCD_CUDA_RESAMPLING_SOLID_ADJACENT_HALO_CELLS_0307="$SOLID_ADJACENT_HALO_CELLS" \
    MPCD_CUDA_RESAMPLING_TINY_MASS_THRESHOLD_0307="$TINY_MASS_THRESHOLD" \
    $safety_env RUN_ROOT="$run_root" $extra bash "$script" >"$stdout_log" 2>"$stderr_log"
  rc=$?
  set -e

  local accepted=0
  if [[ "$rc" == "0" ]]; then
    accepted=1
  elif [[ "$ALLOW_DIAG_ONLY_SUCCESS" == "1" && -s "$run_root/output/cuda_resampling_population_guard_0297.csv" ]]; then
    accepted=1
  fi
  append_manifest "$case_name" "$mode" "$run_root" "$rc" "$accepted" "$script" "$extra $safety_env"
  if [[ "$accepted" != "1" ]]; then
    echo "[0307-split] FAIL case=$case_name mode=$mode rc=$rc" >&2
    echo "[0307-split] stdout/stderr: $stdout_log $stderr_log" >&2
    if [[ "$STOP_ON_FAIL" == "1" ]]; then exit "$rc"; fi
  fi
}

run_case_modes() {
  local case_name=$1 script=$2 root_base=$3; shift 3
  for mode in $SAFETY_MODES; do
    run_one "$case_name" "$mode" "$script" "$root_base/$mode" "$@"
  done
}

if [[ "$RUN_STEP" != "0" ]]; then
  run_case_modes backward_step "scripts/run_demo_src_classic_cuda_backward_step_io_0283.sh" "$ART_DIR/backward_step" \
    NX="$STEP_NX" NY="$STEP_NY" STEPS="$STEP_STEPS" DT="$STEP_DT" UIN="$STEP_UIN" THERMOSTAT_ENABLE=1 OUTLET_MODE=hybrid
fi

if [[ "$RUN_VK" != "0" ]]; then
  run_case_modes von_karman_circle "scripts/run_demo_src_resampling_cuda_von_karman_cylinder_0303.sh" "$ART_DIR/von_karman_circle" \
    NX="$VK_NX" NY="$VK_NY" STEPS="$VK_STEPS" DT="$VK_DT" UIN="$VK_UIN" THERMOSTAT_ENABLE="$VK_THERMOSTAT_ENABLE" VK_THERMOSTAT_ENABLE="$VK_THERMOSTAT_ENABLE"
fi

if [[ "$RUN_TG_HOLE" != "0" ]]; then
  run_case_modes taylor_green_hole "scripts/run_demo_src_resampling_cuda_taylor_green_hole_0305.sh" "$ART_DIR/taylor_green_hole" \
    NX="$TG_NX" NY="$TG_NY" STEPS="$TG_STEPS" DT="$TG_DT"
fi

python3 scripts/analyze_cuda_resampling_split_safety_0307.py "$RUN_MANIFEST" "$ART_DIR"

echo "[0307-split] manifest=$RUN_MANIFEST"
echo "[0307-split] per-run=$ART_DIR/cuda_resampling_split_safety_0307_per_run.csv"
