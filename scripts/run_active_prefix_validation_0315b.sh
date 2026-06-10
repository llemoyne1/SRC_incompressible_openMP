#!/usr/bin/env bash
set -euo pipefail

# 0315b validation harness: compare existing runtime diagnostics for four
# representative CUDA SRC/MPCD cases before continuing the active/inactive
# optimization work.
#
# It does not enable extra solver-side development diagnostics. It reuses the
# existing demo runners and compares summary_runtime.csv for REF_BIN vs TEST_BIN.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ART_DIR=${ART_DIR:-dev_history/artifacts/active_prefix_validation_0315b}
REF_BIN=${REF_BIN:-build/src_mpcd_base_cuda_0314}
TEST_BIN=${TEST_BIN:-build/src_mpcd_base_cuda_0315b}
BUILD_TEST=${BUILD_TEST:-1}
BUILD_REF=${BUILD_REF:-0}
STOP_ON_FAIL=${STOP_ON_FAIL:-0}
CLEAN_ART_DIR=${CLEAN_ART_DIR:-1}
LIVE_PROGRESS=${LIVE_PROGRESS:-0}
THREADS=${THREADS:-8}
GAMMA=${GAMMA:-20}
INACTIVE_SLOTS=${INACTIVE_SLOTS:-100000}
VALIDATION_MODES=${VALIDATION_MODES:-classic}  # classic or "classic resampling"
VALIDATION_CASES=${VALIDATION_CASES:-"tg poiseuille step box"}

# Short but discriminating defaults. Override from shell for longer acceptance runs.
TG_NX=${TG_NX:-64}; TG_NY=${TG_NY:-64}; TG_STEPS=${TG_STEPS:-300}
POISEUILLE_NX=${POISEUILLE_NX:-64}; POISEUILLE_NY=${POISEUILLE_NY:-32}; POISEUILLE_STEPS=${POISEUILLE_STEPS:-500}
STEP_NX=${STEP_NX:-86}; STEP_NY=${STEP_NY:-32}; STEP_STEPS=${STEP_STEPS:-600}
BOX_NX=${BOX_NX:-64}; BOX_NY=${BOX_NY:-64}; BOX_STEPS=${BOX_STEPS:-500}
SUMMARY_EVERY=${SUMMARY_EVERY:-100}
DUMP_STATE_EVERY=${DUMP_STATE_EVERY:-final}
DUMP_ROLE_FILTER=${DUMP_ROLE_FILTER:-fluid}
SUMMARY_ROLE_FILTER=${SUMMARY_ROLE_FILTER:-all}
COMPARE_ABS_TOL=${COMPARE_ABS_TOL:-1e-8}
COMPARE_REL_TOL=${COMPARE_REL_TOL:-1e-8}
ALLOW_RUNTIME_RATIO=${ALLOW_RUNTIME_RATIO:-0}  # e.g. 2.0 to fail if TEST >2x REF; 0 disables.

export OMP_NUM_THREADS=${OMP_NUM_THREADS:-$THREADS}
export OMP_PROC_BIND=${OMP_PROC_BIND:-close}
export OMP_PLACES=${OMP_PLACES:-cores}
export OMP_DYNAMIC=${OMP_DYNAMIC:-false}

if [[ "$CLEAN_ART_DIR" == "1" || "$CLEAN_ART_DIR" == "true" || "$CLEAN_ART_DIR" == "TRUE" ]]; then
  rm -rf "$ART_DIR"
fi
mkdir -p "$ART_DIR"

if [[ "$BUILD_REF" == "1" || "$BUILD_REF" == "true" || "$BUILD_REF" == "TRUE" ]]; then
  echo "[0315b-val] building REF_BIN=$REF_BIN"
  OUT="$REF_BIN" CUDA_ARCH_FLAGS="${CUDA_ARCH_FLAGS:-}" bash scripts/build_src_mpcd_cuda_0314.sh
fi
if [[ "$BUILD_TEST" == "1" || "$BUILD_TEST" == "true" || "$BUILD_TEST" == "TRUE" ]]; then
  echo "[0315b-val] building TEST_BIN=$TEST_BIN"
  OUT="$TEST_BIN" CUDA_ARCH_FLAGS="${CUDA_ARCH_FLAGS:-}" bash scripts/build_src_mpcd_cuda_0315b.sh
fi

if [[ ! -x "$REF_BIN" ]]; then
  echo "[0315b-val] ERROR: REF_BIN is missing or not executable: $REF_BIN" >&2
  echo "[0315b-val] Keep a pre-315b reference binary, or set REF_BIN=/path/to/reference." >&2
  exit 127
fi
if [[ ! -x "$TEST_BIN" ]]; then
  echo "[0315b-val] ERROR: TEST_BIN is missing or not executable: $TEST_BIN" >&2
  exit 127
fi

MANIFEST="$ART_DIR/active_prefix_0315b_run_manifest.csv"
printf 'caseName,modeName,variant,binary,runRoot,requestedSteps,exitCode,summaryFile,timeFile,stdoutFile,stderrFile\n' > "$MANIFEST"

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
    *) echo "[0315b-val] unknown case: $1" >&2; exit 2 ;;
  esac
}

case_nx() { case "$1" in tg) echo "$TG_NX";; poiseuille) echo "$POISEUILLE_NX";; step) echo "$STEP_NX";; box) echo "$BOX_NX";; esac; }
case_ny() { case "$1" in tg) echo "$TG_NY";; poiseuille) echo "$POISEUILLE_NY";; step) echo "$STEP_NY";; box) echo "$BOX_NY";; esac; }
case_steps() { case "$1" in tg) echo "$TG_STEPS";; poiseuille) echo "$POISEUILLE_STEPS";; step) echo "$STEP_STEPS";; box) echo "$BOX_STEPS";; esac; }

mode_env() {
  case "$1" in
    classic)
      printf 'RESAMPLING_ENABLE=0 RESAMPLING_SURVEY_ENABLE=0 GUARD_EVERY=999999 '
      ;;
    resampling)
      printf 'RESAMPLING_ENABLE=1 RESAMPLING_SURVEY_ENABLE=1 GUARD_EVERY=%s ' "${GUARD_EVERY:-20}"
      ;;
    *) echo "[0315b-val] unknown validation mode: $1" >&2; exit 2 ;;
  esac
}

run_one() {
  local case_name=$1 mode_name=$2 variant=$3 bin=$4
  local script nx ny steps dump_every run_root stdout_file stderr_file rc summary time_file env_line
  script=$(case_script "$case_name")
  nx=$(case_nx "$case_name")
  ny=$(case_ny "$case_name")
  steps=$(case_steps "$case_name")
  if [[ "$DUMP_STATE_EVERY" == "final" ]]; then dump_every="$steps"; else dump_every="$DUMP_STATE_EVERY"; fi
  run_root="$ART_DIR/runs/${case_name}/${mode_name}/${variant}"
  mkdir -p "$run_root/wrapper_logs"
  stdout_file="$run_root/wrapper_logs/${case_name}_${mode_name}_${variant}.stdout.log"
  stderr_file="$run_root/wrapper_logs/${case_name}_${mode_name}_${variant}.stderr.log"
  summary="$run_root/output/summary_runtime.csv"
  time_file="$run_root/logs/${case_name}.time"
  env_line=$(mode_env "$mode_name")

  echo "[0315b-val] run case=$case_name mode=$mode_name variant=$variant bin=$bin nx=${nx} ny=${ny} steps=${steps} inactive=${INACTIVE_SLOTS}"
  set +e
  # shellcheck disable=SC2086
  env $env_line \
      BIN="$bin" AUTO_BUILD=0 LIVE_PROGRESS="$LIVE_PROGRESS" CLEAN_RUN_ROOT=1 \
      RUN_ROOT="$run_root" NX="$nx" NY="$ny" GAMMA="$GAMMA" STEPS="$steps" \
      SUMMARY_EVERY="$SUMMARY_EVERY" DUMP_STATE_EVERY="$dump_every" \
      DUMP_ROLE_FILTER="$DUMP_ROLE_FILTER" SUMMARY_ROLE_FILTER="$SUMMARY_ROLE_FILTER" \
      THREADS="$THREADS" INACTIVE_SLOTS="$INACTIVE_SLOTS" \
      bash "$script" >"$stdout_file" 2>"$stderr_file"
  rc=$?
  set -e
  append_manifest "$case_name" "$mode_name" "$variant" "$bin" "$run_root" "$steps" "$rc" "$summary" "$time_file" "$stdout_file" "$stderr_file"
  if [[ "$rc" != "0" ]]; then
    echo "[0315b-val] run failed case=$case_name mode=$mode_name variant=$variant rc=$rc" >&2
    tail -80 "$stderr_file" >&2 || true
    tail -80 "$stdout_file" >&2 || true
    if [[ "$STOP_ON_FAIL" == "1" ]]; then exit "$rc"; fi
  fi
}

for mode in $VALIDATION_MODES; do
  for case_name in $VALIDATION_CASES; do
    run_one "$case_name" "$mode" ref "$REF_BIN"
    run_one "$case_name" "$mode" test "$TEST_BIN"
  done
done

python3 scripts/compare_active_prefix_diagnostics_0315b.py "$MANIFEST" "$ART_DIR" \
  --abs-tol "$COMPARE_ABS_TOL" \
  --rel-tol "$COMPARE_REL_TOL" \
  --allow-runtime-ratio "$ALLOW_RUNTIME_RATIO"

echo "[0315b-val] manifest: $MANIFEST"
echo "[0315b-val] summary : $ART_DIR/active_prefix_0315b_compare_summary.csv"
echo "[0315b-val] details : $ART_DIR/active_prefix_0315b_compare_details.csv"
