#!/usr/bin/env bash
set -euo pipefail

# 0301 — long/moderate backward-step support-control validation.
#
# The purpose is not strict OFF/ON equality.  It compares the time evolution of
# classic SRC CUDA and active local resampling on a backward-step case where the
# recirculation zone is known to lose particles at sufficiently large inlet
# speed.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BIN=${BIN:-build/src_mpcd_base_cuda_0301}
ART_DIR=${ART_DIR:-dev_history/artifacts/gpu_cuda_resampling_backward_step_long_0301}
NX=${NX:-96}
NY=${NY:-48}
GAMMA=${GAMMA:-20}
STEPS=${STEPS:-3000}
DT=${DT:-0.0008}
KBT=${KBT:-0.001}
THREADS=${THREADS:-8}
SUMMARY_EVERY=${SUMMARY_EVERY:-100}
DUMP_STATE_EVERY=${DUMP_STATE_EVERY:-1000}
LIVE_PROGRESS=${LIVE_PROGRESS:-0}
CLEAN_RUN_ROOT=${CLEAN_RUN_ROOT:-1}
FORCE_REBUILD=${FORCE_REBUILD:-1}
STOP_ON_FAIL=${STOP_ON_FAIL:-1}

# Moderate but discriminating by default.  Add velocities explicitly through
# UIN_GRID="0.30 0.45 0.60" when needed.
UIN_GRID=${UIN_GRID:-"0.45"}
STEP_XMAX=${STEP_XMAX:-0.75}
STEP_YMAX=${STEP_YMAX:-0.42}
INACTIVE_SLOTS=${INACTIVE_SLOTS:-$((GAMMA * NY * 8))}
OUTLET_MODE=${OUTLET_MODE:-hybrid}
THERMOSTAT_ENABLE=${THERMOSTAT_ENABLE:-1}

# Passive support survey is enabled on all modes so classic and guard runs can
# be compared with the same support metrics.  It remains non-mutating.
SUPPORT_SURVEY=${SUPPORT_SURVEY:-1}
SURVEY_EVERY=${SURVEY_EVERY:-$SUMMARY_EVERY}

RECONDITION_EVERY=${RECONDITION_EVERY:-50}
RECONDITION_STRENGTH=${RECONDITION_STRENGTH:-1.0}
RUN_MASS_ONLY=${RUN_MASS_ONLY:-0}
GUARD_EVERY=${GUARD_EVERY:-50}
GUARD_GRID=${GUARD_GRID:-"10:20:34 12:20:32 14:20:30"}
GUARD_SPLIT_FRACTION=${GUARD_SPLIT_FRACTION:-0.5}
GUARD_WITH_MASS_RECONDITION=${GUARD_WITH_MASS_RECONDITION:-0}
RESTORE_ENABLE=${RESTORE_ENABLE:-1}
RESTORE_MAX_SCALE=${RESTORE_MAX_SCALE:-4.0}
RESTORE_MIN_CURRENT_KREL=${RESTORE_MIN_CURRENT_KREL:-1e-30}
RESTORE_ABS_TOL=${RESTORE_ABS_TOL:-1e-14}
RESTORE_REL_TOL=${RESTORE_REL_TOL:-1e-12}
BOUNDARY_AWARE=${BOUNDARY_AWARE:-1}
BOUNDARY_HALO_CELLS=${BOUNDARY_HALO_CELLS:-0}
OPEN_BOUNDARY_HALO_CELLS=${OPEN_BOUNDARY_HALO_CELLS:-1}
SOLID_HALO_CELLS=${SOLID_HALO_CELLS:-0}

mkdir -p "$ART_DIR"

if [[ "$FORCE_REBUILD" != "0" && "$FORCE_REBUILD" != "false" && "$FORCE_REBUILD" != "FALSE" ]]; then
  echo "[0301-step-long] rebuilding $BIN"
  OUT="$BIN" CUDA_ARCH_FLAGS="${CUDA_ARCH_FLAGS:-}" bash scripts/build_src_mpcd_cuda_0301.sh
elif [[ ! -x "$BIN" ]]; then
  OUT="$BIN" CUDA_ARCH_FLAGS="${CUDA_ARCH_FLAGS:-}" bash scripts/build_src_mpcd_cuda_0301.sh
fi
if [[ ! -x "$BIN" ]]; then
  echo "[0301-step-long] ERROR: missing binary $BIN" >&2
  exit 127
fi

RUN_MANIFEST=${RUN_MANIFEST:-$ART_DIR/cuda_resampling_backward_step_long_0301_run_manifest.csv}
printf 'caseName,modeName,uin,nmin,ntarget,nmax,runRoot,exitCode,script,extraEnv\n' > "$RUN_MANIFEST"

append_manifest() {
  python3 - "$RUN_MANIFEST" "$@" <<'PY'
import csv, sys
out=sys.argv[1]
with open(out, 'a', newline='') as fh:
    csv.writer(fh).writerow(sys.argv[2:])
PY
}

uin_label() {
  printf '%s' "$1" | sed 's/-/m/g; s/\./p/g'
}

run_one() {
  local uin=$1 mode_name=$2 nmin=$3 ntarget=$4 nmax=$5 extra_env=${6:-}
  local label="uin$(uin_label "$uin")"
  local case_name="backward_step_${label}"
  local script="scripts/run_cuda_resampling_backward_step_validation_0301.sh"
  local run_root="$ART_DIR/$case_name/$mode_name"
  echo "[0301-step-long] running case=$case_name mode=$mode_name nmin=$nmin ntarget=$ntarget nmax=$nmax"
  mkdir -p "$(dirname "$run_root")"
  local rc=0
  set +e
  env BIN="$BIN" AUTO_BUILD=0 LIVE_PROGRESS="$LIVE_PROGRESS" CLEAN_RUN_ROOT="$CLEAN_RUN_ROOT" \
      NX="$NX" NY="$NY" GAMMA="$GAMMA" STEPS="$STEPS" DT="$DT" KBT="$KBT" \
      SUMMARY_EVERY="$SUMMARY_EVERY" DUMP_STATE_EVERY="$DUMP_STATE_EVERY" THREADS="$THREADS" \
      UIN="$uin" STEP_XMAX="$STEP_XMAX" STEP_YMAX="$STEP_YMAX" RUN_ROOT="$run_root" \
      INACTIVE_SLOTS="$INACTIVE_SLOTS" OUTLET_MODE="$OUTLET_MODE" THERMOSTAT_ENABLE="$THERMOSTAT_ENABLE" \
      MPCD_CUDA_RESAMPLING_SUPPORT_SURVEY_0295="$SUPPORT_SURVEY" \
      MPCD_CUDA_RESAMPLING_SUPPORT_SURVEY_0295_EVERY="$SURVEY_EVERY" \
      MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296=0 \
      MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296_EVERY="$RECONDITION_EVERY" \
      MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296_STRENGTH="$RECONDITION_STRENGTH" \
      MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297=0 \
      MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_EVERY="$GUARD_EVERY" \
      MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_NMIN="$nmin" \
      MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_NTARGET="$ntarget" \
      MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_NMAX="$nmax" \
      MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_SPLIT_FRACTION="$GUARD_SPLIT_FRACTION" \
      MPCD_CUDA_RESAMPLING_MOMENT_RESTORE_0298="$RESTORE_ENABLE" \
      MPCD_CUDA_RESAMPLING_MOMENT_RESTORE_0298_MAX_SCALE="$RESTORE_MAX_SCALE" \
      MPCD_CUDA_RESAMPLING_MOMENT_RESTORE_0298_MIN_CURRENT_KREL="$RESTORE_MIN_CURRENT_KREL" \
      MPCD_CUDA_RESAMPLING_MOMENT_RESTORE_0298_ABS_TOL="$RESTORE_ABS_TOL" \
      MPCD_CUDA_RESAMPLING_MOMENT_RESTORE_0298_REL_TOL="$RESTORE_REL_TOL" \
      MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0299_BOUNDARY_AWARE="$BOUNDARY_AWARE" \
      MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0299_BOUNDARY_HALO_CELLS="$BOUNDARY_HALO_CELLS" \
      MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0299_OPEN_BOUNDARY_HALO_CELLS="$OPEN_BOUNDARY_HALO_CELLS" \
      MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0299_SOLID_HALO_CELLS="$SOLID_HALO_CELLS" \
      $extra_env bash "$script" >"$run_root.stdout.log" 2>"$run_root.stderr.log"
  rc=$?
  set -e
  append_manifest "$case_name" "$mode_name" "$uin" "$nmin" "$ntarget" "$nmax" "$run_root" "$rc" "$script" "$extra_env"
  if [[ "$rc" != "0" ]]; then
    echo "[0301-step-long] FAIL case=$case_name mode=$mode_name rc=$rc" >&2
    echo "[0301-step-long] stdout/stderr: $run_root.stdout.log $run_root.stderr.log" >&2
    if [[ "$STOP_ON_FAIL" == "1" ]]; then
      exit "$rc"
    fi
  fi
}

for uin in $UIN_GRID; do
  run_one "$uin" classic 0 0 0 ""
  if [[ "$RUN_MASS_ONLY" != "0" ]]; then
    run_one "$uin" mass0296 0 0 0 "MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296=1"
  fi
  for triple in $GUARD_GRID; do
    IFS=: read -r nmin ntarget nmax <<<"$triple"
    mode="guard0299_nmin${nmin}_nt${ntarget}_nmax${nmax}"
    run_one "$uin" "$mode" "$nmin" "$ntarget" "$nmax" \
      "MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296=$GUARD_WITH_MASS_RECONDITION MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297=1"
  done
done

python3 scripts/analyze_cuda_resampling_backward_step_long_0301.py "$RUN_MANIFEST" "$ART_DIR"

echo "[0301-step-long] manifest=$RUN_MANIFEST"
echo "[0301-step-long] per-run=$ART_DIR/cuda_resampling_backward_step_long_0301_per_run.csv"
echo "[0301-step-long] vs-classic=$ART_DIR/cuda_resampling_backward_step_long_0301_vs_classic.csv"
echo "[0301-step-long] time-series=$ART_DIR/cuda_resampling_backward_step_long_0301_timeseries.csv"
