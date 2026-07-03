#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

# Short, headless performance matrix for the 0434 backward-step case.
# All paths use the same physical and numerical inputs. Only the resampling
# algorithmic scope changes. Set LIVE_VIS_ENABLE=1 explicitly for inspection.
NX="${NX:-960}"
NY="${NY:-480}"
GAMMA="${GAMMA:-7}"
STEPS="${STEPS:-20}"
SUMMARY_EVERY="${SUMMARY_EVERY:-5}"
THREADS="${THREADS:-8}"
MATRIX_ROOT="${MATRIX_ROOT:-runs/0434_step_resampling_path_matrix_${NX}x${NY}_g${GAMMA}_${STEPS}}"
CASES="${CASES:-src src-q6 cuda-local cpu-reduced full}"

LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-0}"
FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-0}"
LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-0}"
MPCD_INTERNAL_PROFILES="${MPCD_INTERNAL_PROFILES:-1}"

run_case() {
  local case_name=$1
  local run_mode weighted refill extraction insertion remap thermal mass_guard

  case "$case_name" in
    src)
      run_mode=src; weighted=false; refill=false
      extraction=true; insertion=true; remap=true; thermal=true; mass_guard=true
      ;;
    src-q6)
      run_mode=src-q6; weighted=false; refill=false
      extraction=true; insertion=true; remap=true; thermal=true; mass_guard=true
      ;;
    cuda-local)
      # Export the validated CUDA 0295/0296/0297 flags, but skip the complete
      # host weighted-resampling pipeline and its per-step GPU->CPU handoff.
      run_mode=src-resampling; weighted=false; refill=true
      extraction=false; insertion=false; remap=false; thermal=false; mass_guard=false
      ;;
    cpu-reduced)
      # Keep the CPU population guard/deposits, but remove the global transfer
      # planner and all remap/thermal/mass-guard stages.
      run_mode=src-resampling; weighted=true; refill=true
      extraction=false; insertion=false; remap=false; thermal=false; mass_guard=false
      ;;
    full)
      run_mode=src-resampling; weighted=true; refill=true
      extraction=true; insertion=true; remap=true; thermal=true; mass_guard=true
      ;;
    *)
      echo "[0434-step-matrix] unknown case '$case_name'" >&2
      return 2
      ;;
  esac

  echo "[0434-step-matrix] case=$case_name runMode=$run_mode weighted=$weighted"
  env \
    RUN_MODES="$run_mode" \
    BASE_RUN_ROOT="$MATRIX_ROOT/$case_name" \
    NX="$NX" NY="$NY" GAMMA="$GAMMA" STEPS="$STEPS" \
    SUMMARY_EVERY="$SUMMARY_EVERY" DUMP_STATE_EVERY=0 THREADS="$THREADS" \
    LIVE_VIS_ENABLE="$LIVE_VIS_ENABLE" FILTERED_RECORDING_ENABLE="$FILTERED_RECORDING_ENABLE" \
    LIVE_VIS_HOLD_ON_EXIT="$LIVE_VIS_HOLD_ON_EXIT" MPCD_INTERNAL_PROFILES="$MPCD_INTERNAL_PROFILES" \
    WEIGHTED_RESAMPLING_ENABLE_OVERRIDE="$weighted" \
    CUDA_EMPTY_REFILL_ENABLE_OVERRIDE="$refill" \
    RESAMPLING_EXTRACTION_ENABLE="$extraction" \
    RESAMPLING_INSERTION_ENABLE="$insertion" \
    RESAMPLING_REMAP_ENABLE="$remap" \
    RESAMPLING_THERMAL_RENORMALIZATION_ENABLE="$thermal" \
    RESAMPLING_MASS_GUARD_ENABLE="$mass_guard" \
    bash scripts/run_0434_step.sh
}

for case_name in $CASES; do
  run_case "$case_name"
done

python3 - "$MATRIX_ROOT" "$CASES" <<'PY'
import csv
import os
import re
import sys

root = sys.argv[1]
cases = sys.argv[2].split()
mode_dir = {
    "src": "src",
    "src-q6": "src-q6",
    "cuda-local": "src-resampling",
    "cpu-reduced": "src-resampling",
    "full": "src-resampling",
}
phase_names = [
    "total_profiled",
    "src_collision",
    "q6_projection",
    "resampling_deposit_initial",
    "resampling_post_guard_deposit",
    "resampling_insertion",
    "resampling_mass_guard",
]
rows = []
for case in cases:
    mode = mode_dir[case]
    run = os.path.join(root, case, mode)
    time_path = os.path.join(run, "logs", "backward_step_darcy.time")
    profile_path = os.path.join(run, "output", "phase_profile_0163.csv")
    elapsed = ""
    if os.path.exists(time_path):
        match = re.search(r"elapsed=([0-9.eE+-]+)", open(time_path, encoding="utf-8").read())
        if match:
            elapsed = match.group(1)
    phases = {}
    if os.path.exists(profile_path):
        with open(profile_path, newline="", encoding="utf-8") as stream:
            phases = {row["phase"]: row["total_s"] for row in csv.DictReader(stream)}
    row = {"case": case, "elapsed_s": elapsed}
    row.update({name + "_s": phases.get(name, "") for name in phase_names})
    rows.append(row)

os.makedirs(root, exist_ok=True)
summary = os.path.join(root, "comparison.csv")
fields = ["case", "elapsed_s"] + [name + "_s" for name in phase_names]
with open(summary, "w", newline="", encoding="utf-8") as stream:
    writer = csv.DictWriter(stream, fieldnames=fields)
    writer.writeheader()
    writer.writerows(rows)
print(f"[0434-step-matrix] summary={summary}")
for row in rows:
    print("[0434-step-matrix]", row)
PY

echo "[0434-step-matrix] complete root=$MATRIX_ROOT"
