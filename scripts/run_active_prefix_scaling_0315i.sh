#!/usr/bin/env bash
set -euo pipefail

# 0315i — Active/inactive scaling benchmark harness.
# Runs one CUDA SRC/MPCD binary across several inactive-slot capacities and
# summarizes elapsed times. This script is intentionally outside the solver
# code path: it enables no development diagnostics and writes only benchmark CSVs.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ART_DIR=${ART_DIR:-dev_history/artifacts/active_prefix_scaling_0315i}
BIN=${BIN:-build/src_mpcd_base_cuda_0315h_fix10}
BUILD_BIN=${BUILD_BIN:-0}
CLEAN_ART_DIR=${CLEAN_ART_DIR:-1}
LIVE_PROGRESS=${LIVE_PROGRESS:-0}
THREADS=${THREADS:-8}
GAMMA=${GAMMA:-20}
REPEATS=${REPEATS:-1}
SCALING_CASES=${SCALING_CASES:-"tg poiseuille step box"}
INACTIVE_SLOT_LIST=${INACTIVE_SLOT_LIST:-"0 100000 1000000 2000000"}

# Short, comparable defaults matching the 0315b validation harness. Override
# from the shell for acceptance/performance runs.
TG_NX=${TG_NX:-64}; TG_NY=${TG_NY:-64}; TG_STEPS=${TG_STEPS:-300}
POISEUILLE_NX=${POISEUILLE_NX:-64}; POISEUILLE_NY=${POISEUILLE_NY:-32}; POISEUILLE_STEPS=${POISEUILLE_STEPS:-500}
STEP_NX=${STEP_NX:-86}; STEP_NY=${STEP_NY:-32}; STEP_STEPS=${STEP_STEPS:-600}
BOX_NX=${BOX_NX:-64}; BOX_NY=${BOX_NY:-64}; BOX_STEPS=${BOX_STEPS:-500}

SUMMARY_EVERY=${SUMMARY_EVERY:-1000000000}
DUMP_STATE_EVERY=${DUMP_STATE_EVERY:-0}
REQUIRE_DEMO_DUMPS=${REQUIRE_DEMO_DUMPS:-0}
DUMP_ROLE_FILTER=${DUMP_ROLE_FILTER:-fluid}
SUMMARY_ROLE_FILTER=${SUMMARY_ROLE_FILTER:-fluid}

# Classic mode by default; resampling/Q6/virial can be enabled manually via
# case scripts/environment if desired, but this benchmark is intended first for
# inactive-slot scaling of classic resident CUDA.
RESAMPLING_ENABLE=${RESAMPLING_ENABLE:-0}
RESAMPLING_SURVEY_ENABLE=${RESAMPLING_SURVEY_ENABLE:-0}
GUARD_EVERY=${GUARD_EVERY:-999999}

export OMP_NUM_THREADS=${OMP_NUM_THREADS:-$THREADS}
export OMP_PROC_BIND=${OMP_PROC_BIND:-close}
export OMP_PLACES=${OMP_PLACES:-cores}
export OMP_DYNAMIC=${OMP_DYNAMIC:-false}

if [[ "$CLEAN_ART_DIR" == "1" || "$CLEAN_ART_DIR" == "true" || "$CLEAN_ART_DIR" == "TRUE" ]]; then
  rm -rf "$ART_DIR"
fi
mkdir -p "$ART_DIR"

if [[ "$BUILD_BIN" == "1" || "$BUILD_BIN" == "true" || "$BUILD_BIN" == "TRUE" ]]; then
  echo "[0315i-scale] building BIN=$BIN"
  OUT="$BIN" CUDA_ARCH_FLAGS="${CUDA_ARCH_FLAGS:-}" bash scripts/build_src_mpcd_cuda_0315b.sh
fi
if [[ ! -x "$BIN" ]]; then
  echo "[0315i-scale] ERROR: BIN is missing or not executable: $BIN" >&2
  exit 127
fi

MANIFEST="$ART_DIR/active_prefix_0315i_scaling_manifest.csv"
printf 'caseName,inactiveSlots,repeat,binary,runRoot,requestedSteps,exitCode,summaryFile,timeFile,stdoutFile,stderrFile\n' > "$MANIFEST"

append_manifest() {
  python3 - "$MANIFEST" "$@" <<'PY'
import csv, sys
with open(sys.argv[1], 'a', newline='') as fh:
    csv.writer(fh).writerow(sys.argv[2:])
PY
}

case_script() {
  case "$1" in
    tg) printf '%s' scripts/run_demo_src_classic_cuda_taylor_green_forced_0283.sh ;;
    poiseuille) printf '%s' scripts/run_demo_src_classic_cuda_poiseuille_periodic_forced_0283.sh ;;
    step) printf '%s' scripts/run_demo_src_classic_cuda_backward_step_io_0283.sh ;;
    box) printf '%s' scripts/run_demo_src_classic_cuda_box_same_face_io_0283.sh ;;
    *) echo "[0315i-scale] unknown case: $1" >&2; exit 2 ;;
  esac
}
case_nx() { case "$1" in tg) echo "$TG_NX";; poiseuille) echo "$POISEUILLE_NX";; step) echo "$STEP_NX";; box) echo "$BOX_NX";; esac; }
case_ny() { case "$1" in tg) echo "$TG_NY";; poiseuille) echo "$POISEUILLE_NY";; step) echo "$STEP_NX" >/dev/null; echo "$STEP_NY";; box) echo "$BOX_NY";; esac; }
case_steps() { case "$1" in tg) echo "$TG_STEPS";; poiseuille) echo "$POISEUILLE_STEPS";; step) echo "$STEP_STEPS";; box) echo "$BOX_STEPS";; esac; }

run_one() {
  local case_name=$1 inactive_slots=$2 repeat_id=$3
  local script nx ny steps run_root stdout_file stderr_file summary time_file rc dump_every
  script=$(case_script "$case_name")
  nx=$(case_nx "$case_name")
  ny=$(case_ny "$case_name")
  steps=$(case_steps "$case_name")
  dump_every="$DUMP_STATE_EVERY"
  run_root="$ART_DIR/runs/${case_name}/inactive_${inactive_slots}/rep_${repeat_id}"
  # Keep wrapper logs outside RUN_ROOT: the demo wrappers may rm -rf RUN_ROOT
  # during prepare_demo_dirs_0283, which otherwise deletes the redirected files.
  local wrapper_log_dir="$ART_DIR/wrapper_logs/${case_name}/inactive_${inactive_slots}/rep_${repeat_id}"
  mkdir -p "$wrapper_log_dir"
  stdout_file="$wrapper_log_dir/${case_name}_inactive_${inactive_slots}_rep_${repeat_id}.stdout.log"
  stderr_file="$wrapper_log_dir/${case_name}_inactive_${inactive_slots}_rep_${repeat_id}.stderr.log"
  summary="$run_root/output/summary_runtime.csv"
  time_file="$run_root/logs/${case_name}.time"

  echo "[0315i-scale] run case=$case_name inactive=$inactive_slots repeat=$repeat_id bin=$BIN nx=$nx ny=$ny steps=$steps"
  set +e
  env \
      BIN="$BIN" AUTO_BUILD=0 LIVE_PROGRESS="$LIVE_PROGRESS" CLEAN_RUN_ROOT=1 \
      RUN_ROOT="$run_root" NX="$nx" NY="$ny" GAMMA="$GAMMA" STEPS="$steps" \
      SUMMARY_EVERY="$SUMMARY_EVERY" DUMP_STATE_EVERY="$dump_every" \
      SRC_GPU_DEMO_REQUIRE_DUMPS="$REQUIRE_DEMO_DUMPS" \
      DUMP_ROLE_FILTER="$DUMP_ROLE_FILTER" SUMMARY_ROLE_FILTER="$SUMMARY_ROLE_FILTER" \
      THREADS="$THREADS" INACTIVE_SLOTS="$inactive_slots" \
      RESAMPLING_ENABLE="$RESAMPLING_ENABLE" RESAMPLING_SURVEY_ENABLE="$RESAMPLING_SURVEY_ENABLE" GUARD_EVERY="$GUARD_EVERY" \
      bash "$script" >"$stdout_file" 2>"$stderr_file"
  rc=$?
  set -e
  append_manifest "$case_name" "$inactive_slots" "$repeat_id" "$BIN" "$run_root" "$steps" "$rc" "$summary" "$time_file" "$stdout_file" "$stderr_file"
  if [[ "$rc" != "0" ]]; then
    echo "[0315i-scale] run failed case=$case_name inactive=$inactive_slots repeat=$repeat_id rc=$rc" >&2
    if [[ -f "$stderr_file" ]]; then tail -80 "$stderr_file" >&2 || true; else echo "[0315i-scale] missing wrapper stderr: $stderr_file" >&2; fi
    if [[ -f "$stdout_file" ]]; then tail -80 "$stdout_file" >&2 || true; else echo "[0315i-scale] missing wrapper stdout: $stdout_file" >&2; fi
  fi
}

for inactive_slots in $INACTIVE_SLOT_LIST; do
  for case_name in $SCALING_CASES; do
    for repeat_id in $(seq 1 "$REPEATS"); do
      run_one "$case_name" "$inactive_slots" "$repeat_id"
    done
  done
done

python3 scripts/summarize_active_prefix_scaling_0315i.py "$MANIFEST" "$ART_DIR"

echo "[0315i-scale] manifest: $MANIFEST"
echo "[0315i-scale] runs    : $ART_DIR/runs"
echo "[0315i-scale] summary : $ART_DIR/active_prefix_0315i_scaling_summary.csv"
echo "[0315i-scale] details : $ART_DIR/active_prefix_0315i_scaling_details.csv"
