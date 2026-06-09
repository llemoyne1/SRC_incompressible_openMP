#!/usr/bin/env bash
set -euo pipefail

# 0310 — short inactive-slot scaling audit.
#
# The goal is to measure whether runtime scales with the inactive reservoir size
# without repeating the long 0308 stress validation.  Defaults intentionally keep
# the sweep short and avoid INACTIVE_SLOTS=250000.  Increase *_STEPS or add 250000
# explicitly only for a targeted follow-up.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BIN=${BIN:-build/src_mpcd_base_cuda_0310}
ART_DIR=${ART_DIR:-dev_history/artifacts/gpu_cuda_inactive_slots_scaling_0310}
FORCE_REBUILD=${FORCE_REBUILD:-1}
CLEAN_ART_DIR=${CLEAN_ART_DIR:-1}
STOP_ON_FAIL=${STOP_ON_FAIL:-0}
LIVE_PROGRESS=${LIVE_PROGRESS:-0}
THREADS=${THREADS:-8}

# Fast defaults.  250000 is deliberately excluded; add it manually if needed.
INACTIVE_SLOTS_GRID=${INACTIVE_SLOTS_GRID:-"8000 20000 50000 100000"}
GUARD_EVERY_GRID=${GUARD_EVERY_GRID:-"20"}
MODES=${MODES:-"resampling"}       # use "classic resampling" for a fuller audit
RUN_STEP=${RUN_STEP:-1}
RUN_VK=${RUN_VK:-0}                 # VK is optional because it is slower

STEP_NX=${STEP_NX:-96}; STEP_NY=${STEP_NY:-48}; STEP_STEPS=${STEP_STEPS:-600}; STEP_UIN=${STEP_UIN:-0.60}; STEP_DT=${STEP_DT:-0.0008}
VK_NX=${VK_NX:-96}; VK_NY=${VK_NY:-48}; VK_STEPS=${VK_STEPS:-600}; VK_UIN=${VK_UIN:-0.45}; VK_DT=${VK_DT:-0.0005}; VK_THERMOSTAT_ENABLE=${VK_THERMOSTAT_ENABLE:-1}
SUMMARY_EVERY=${SUMMARY_EVERY:-100}
DUMP_STATE_EVERY=${DUMP_STATE_EVERY:-999999}
GAMMA=${GAMMA:-20}
KBT=${KBT:-0.001}

# Keep the nominal split-safe mode on for resampling runs.
SPLIT_SAFETY_ENABLE=${SPLIT_SAFETY_ENABLE:-1}
SPLIT_PREFER_MAX_MASS_DONOR=${SPLIT_PREFER_MAX_MASS_DONOR:-1}
SPLIT_DONOR_MIN_MASS=${SPLIT_DONOR_MIN_MASS:-0.5}
SPLIT_NEW_PARTICLE_MIN_MASS=${SPLIT_NEW_PARTICLE_MIN_MASS:-0.25}
SOLID_ADJACENT_SPLIT_MODE=${SOLID_ADJACENT_SPLIT_MODE:-0}

if [[ "$CLEAN_ART_DIR" != "0" ]]; then
  rm -rf "$ART_DIR"
fi
mkdir -p "$ART_DIR"

if [[ "$FORCE_REBUILD" != "0" && "$FORCE_REBUILD" != "false" && "$FORCE_REBUILD" != "FALSE" ]]; then
  OUT="$BIN" CUDA_ARCH_FLAGS="${CUDA_ARCH_FLAGS:-}" bash scripts/build_src_mpcd_cuda_0310.sh
elif [[ ! -x "$BIN" ]]; then
  OUT="$BIN" CUDA_ARCH_FLAGS="${CUDA_ARCH_FLAGS:-}" bash scripts/build_src_mpcd_cuda_0310.sh
fi

RUN_MANIFEST=${RUN_MANIFEST:-$ART_DIR/cuda_inactive_slots_scaling_0310_run_manifest.csv}
printf 'caseName,modeName,inactiveSlots,guardEvery,requestedSteps,runRoot,exitCode,script,extraEnv\n' > "$RUN_MANIFEST"

append_manifest() {
  python3 - "$RUN_MANIFEST" "$@" <<'PY'
import csv, sys
with open(sys.argv[1], 'a', newline='') as fh:
    csv.writer(fh).writerow(sys.argv[2:])
PY
}

run_one() {
  local case_name=$1 mode_name=$2 slots=$3 guard_every=$4 requested_steps=$5 script=$6 base_root=$7; shift 7
  local run_root="$base_root/${case_name}_${mode_name}_slots${slots}_guard${guard_every}"
  echo "[0310-inactive] case=$case_name mode=$mode_name slots=$slots guardEvery=$guard_every steps=$requested_steps"

  # Create the parent directory used for stdout/stderr redirection before
  # invoking the demo wrapper.  Without this, bash fails at redirection time and
  # the benchmark never starts, producing empty per-run rows with exitCode=1.
  mkdir -p "$(dirname "$run_root")"

  local rc=0
  set +e
  env \
    BIN="$BIN" FORCE_REBUILD=0 AUTO_BUILD=0 LIVE_PROGRESS="$LIVE_PROGRESS" \
    VIS_MODES="$mode_name" BASE_RUN_ROOT="$run_root" \
    THREADS="$THREADS" GAMMA="$GAMMA" KBT="$KBT" \
    SUMMARY_EVERY="$SUMMARY_EVERY" DUMP_STATE_EVERY="$DUMP_STATE_EVERY" \
    INACTIVE_SLOTS="$slots" GUARD_EVERY="$guard_every" \
    MPCD_CUDA_RESAMPLING_SPLIT_SAFETY_0307="$SPLIT_SAFETY_ENABLE" \
    MPCD_CUDA_RESAMPLING_SPLIT_PREFER_MAX_MASS_DONOR_0307="$SPLIT_PREFER_MAX_MASS_DONOR" \
    MPCD_CUDA_RESAMPLING_SPLIT_DONOR_MIN_MASS_0307="$SPLIT_DONOR_MIN_MASS" \
    MPCD_CUDA_RESAMPLING_SPLIT_NEW_PARTICLE_MIN_MASS_0307="$SPLIT_NEW_PARTICLE_MIN_MASS" \
    MPCD_CUDA_RESAMPLING_SOLID_ADJACENT_SPLIT_MODE_0307="$SOLID_ADJACENT_SPLIT_MODE" \
    "$@" bash "$script" >"$run_root.${mode_name}.stdout.log" 2>"$run_root.${mode_name}.stderr.log"
  rc=$?
  set -e

  # 0309 visual wrappers place the actual run in BASE_RUN_ROOT/{classic,resampling_split_safe}.
  local actual_root="$run_root"
  if [[ "$mode_name" == "classic" ]]; then
    actual_root="$run_root/classic"
  elif [[ "$mode_name" == "resampling" ]]; then
    actual_root="$run_root/resampling_split_safe"
  fi

  append_manifest "$case_name" "$mode_name" "$slots" "$guard_every" "$requested_steps" "$actual_root" "$rc" "$script" "$*"
  if [[ "$rc" != "0" ]]; then
    echo "[0310-inactive] WARN/FAIL case=$case_name mode=$mode_name slots=$slots rc=$rc" >&2
    echo "[0310-inactive] logs: $run_root.${mode_name}.stdout.log $run_root.${mode_name}.stderr.log" >&2
    if [[ "$STOP_ON_FAIL" == "1" ]]; then exit "$rc"; fi
  fi
}

for guard_every in $GUARD_EVERY_GRID; do
  for slots in $INACTIVE_SLOTS_GRID; do
    if [[ "$RUN_STEP" != "0" ]]; then
      for mode in $MODES; do
        run_one backward_step "$mode" "$slots" "$guard_every" "$STEP_STEPS" \
          scripts/run_demo_visual_backward_step_resampling_0309.sh "$ART_DIR/raw" \
          NX="$STEP_NX" NY="$STEP_NY" STEPS="$STEP_STEPS" DT="$STEP_DT" UIN="$STEP_UIN"
      done
    fi
    if [[ "$RUN_VK" != "0" ]]; then
      for mode in $MODES; do
        run_one von_karman_circle "$mode" "$slots" "$guard_every" "$VK_STEPS" \
          scripts/run_demo_visual_von_karman_resampling_0309.sh "$ART_DIR/raw" \
          NX="$VK_NX" NY="$VK_NY" STEPS="$VK_STEPS" DT="$VK_DT" UIN="$VK_UIN" \
          VK_THERMOSTAT_ENABLE="$VK_THERMOSTAT_ENABLE" THERMOSTAT_ENABLE="$VK_THERMOSTAT_ENABLE"
      done
    fi
  done
done

python3 scripts/analyze_cuda_inactive_slots_scaling_0310.py "$RUN_MANIFEST" "$ART_DIR"

echo "[0310-inactive] manifest=$RUN_MANIFEST"
echo "[0310-inactive] per-run=$ART_DIR/cuda_inactive_slots_scaling_0310_per_run.csv"
echo "[0310-inactive] ratios=$ART_DIR/cuda_inactive_slots_scaling_0310_ratios.csv"
