#!/usr/bin/env bash
set -euo pipefail

# 0304 — diagnostic-only post-SRC adaptive flag sweep on backward step.
# It does not enable adaptive guard execution.  It only emits low-N / empty-cell
# trigger counters from the post-SRC/post-thermostat physical-grid deposit.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BIN=${BIN:-build/src_mpcd_base_cuda_0304}
ART_DIR=${ART_DIR:-dev_history/artifacts/gpu_cuda_resampling_adaptive_flag_0304}
NX=${NX:-96}
NY=${NY:-48}
GAMMA=${GAMMA:-20}
STEPS=${STEPS:-3000}
DT=${DT:-0.0008}
KBT=${KBT:-0.001}
THREADS=${THREADS:-8}
SUMMARY_EVERY=${SUMMARY_EVERY:-100}
DUMP_STATE_EVERY=${DUMP_STATE_EVERY:-1000}
FORCE_REBUILD=${FORCE_REBUILD:-1}
CLEAN_RUN_ROOT=${CLEAN_RUN_ROOT:-1}
LIVE_PROGRESS=${LIVE_PROGRESS:-0}
STOP_ON_FAIL=${STOP_ON_FAIL:-1}

UIN_GRID=${UIN_GRID:-"0.60"}
FLAG_EVERY_GRID=${FLAG_EVERY_GRID:-"1 5 20"}
TRIGGER_NMIN_GRID=${TRIGGER_NMIN_GRID:-"4 6 8"}
TRIGGER_EMPTY=${TRIGGER_EMPTY:-1}

# Keep the support survey off by default so the measured diagnostic is the new
# compact flag path, not the full 0295 survey.
SUPPORT_SURVEY=${SUPPORT_SURVEY:-0}

# Optional active guard baseline for comparing whether a fixed guard changes the
# flag statistics.  This is not an adaptive trigger yet.
RUN_CLASSIC_FLAG=${RUN_CLASSIC_FLAG:-1}
RUN_GUARD_FLAG=${RUN_GUARD_FLAG:-1}
GUARD_EVERY=${GUARD_EVERY:-20}
GUARD_NMIN=${GUARD_NMIN:-12}
GUARD_NTARGET=${GUARD_NTARGET:-20}
GUARD_NMAX=${GUARD_NMAX:-32}
RESTORE_ENABLE=${RESTORE_ENABLE:-1}
BOUNDARY_AWARE=${BOUNDARY_AWARE:-1}
OPEN_BOUNDARY_HALO_CELLS=${OPEN_BOUNDARY_HALO_CELLS:-1}
INACTIVE_SLOTS=${INACTIVE_SLOTS:-$((GAMMA * NY * 8))}
THERMOSTAT_ENABLE=${THERMOSTAT_ENABLE:-1}
OUTLET_MODE=${OUTLET_MODE:-hybrid}

mkdir -p "$ART_DIR"

if [[ "$FORCE_REBUILD" != "0" && "$FORCE_REBUILD" != "false" && "$FORCE_REBUILD" != "FALSE" ]]; then
  echo "[0304-flag] rebuilding $BIN"
  OUT="$BIN" CUDA_ARCH_FLAGS="${CUDA_ARCH_FLAGS:-}" bash scripts/build_src_mpcd_cuda_0304.sh
elif [[ ! -x "$BIN" ]]; then
  OUT="$BIN" CUDA_ARCH_FLAGS="${CUDA_ARCH_FLAGS:-}" bash scripts/build_src_mpcd_cuda_0304.sh
fi
if [[ ! -x "$BIN" ]]; then
  echo "[0304-flag] ERROR: missing binary $BIN" >&2
  exit 127
fi

RUN_MANIFEST=${RUN_MANIFEST:-$ART_DIR/cuda_resampling_adaptive_flag_0304_run_manifest.csv}
printf 'caseName,modeName,uin,flagEvery,triggerNMin,triggerEmpty,runRoot,exitCode,script,extraEnv\n' > "$RUN_MANIFEST"

append_manifest() {
  python3 - "$RUN_MANIFEST" "$@" <<'PY'
import csv, sys
with open(sys.argv[1], 'a', newline='') as fh:
    csv.writer(fh).writerow(sys.argv[2:])
PY
}

uin_label() { printf '%s' "$1" | sed 's/-/m/g; s/\./p/g'; }

run_one() {
  local uin=$1 mode=$2 flag_every=$3 trigger_nmin=$4 extra_env=${5:-}
  local case_name="backward_step_uin$(uin_label "$uin")"
  local script="scripts/run_cuda_resampling_backward_step_validation_0301.sh"
  local run_root="$ART_DIR/$case_name/$mode/flagEvery${flag_every}_triggerN${trigger_nmin}"
  echo "[0304-flag] running case=$case_name mode=$mode flagEvery=$flag_every triggerN=$trigger_nmin"
  mkdir -p "$(dirname "$run_root")"
  local rc=0
  set +e
  env BIN="$BIN" AUTO_BUILD=0 LIVE_PROGRESS="$LIVE_PROGRESS" CLEAN_RUN_ROOT="$CLEAN_RUN_ROOT" \
      NX="$NX" NY="$NY" GAMMA="$GAMMA" STEPS="$STEPS" DT="$DT" KBT="$KBT" \
      SUMMARY_EVERY="$SUMMARY_EVERY" DUMP_STATE_EVERY="$DUMP_STATE_EVERY" THREADS="$THREADS" \
      UIN="$uin" RUN_ROOT="$run_root" INACTIVE_SLOTS="$INACTIVE_SLOTS" \
      THERMOSTAT_ENABLE="$THERMOSTAT_ENABLE" OUTLET_MODE="$OUTLET_MODE" \
      MPCD_CUDA_RESAMPLING_SUPPORT_SURVEY_0295="$SUPPORT_SURVEY" \
      MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304=1 \
      MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304_EVERY="$flag_every" \
      MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304_TRIGGER_NMIN="$trigger_nmin" \
      MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304_TRIGGER_EMPTY="$TRIGGER_EMPTY" \
      MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297=0 \
      MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_EVERY="$GUARD_EVERY" \
      MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_NMIN="$GUARD_NMIN" \
      MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_NTARGET="$GUARD_NTARGET" \
      MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297_NMAX="$GUARD_NMAX" \
      MPCD_CUDA_RESAMPLING_MOMENT_RESTORE_0298="$RESTORE_ENABLE" \
      MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0299_BOUNDARY_AWARE="$BOUNDARY_AWARE" \
      MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0299_OPEN_BOUNDARY_HALO_CELLS="$OPEN_BOUNDARY_HALO_CELLS" \
      $extra_env bash "$script" >"$run_root.stdout.log" 2>"$run_root.stderr.log"
  rc=$?
  set -e
  append_manifest "$case_name" "$mode" "$uin" "$flag_every" "$trigger_nmin" "$TRIGGER_EMPTY" "$run_root" "$rc" "$script" "$extra_env"
  if [[ "$rc" != "0" ]]; then
    echo "[0304-flag] FAIL case=$case_name mode=$mode rc=$rc" >&2
    echo "[0304-flag] stdout/stderr: $run_root.stdout.log $run_root.stderr.log" >&2
    if [[ "$STOP_ON_FAIL" == "1" ]]; then exit "$rc"; fi
  fi
}

for uin in $UIN_GRID; do
  for flag_every in $FLAG_EVERY_GRID; do
    for trigger_nmin in $TRIGGER_NMIN_GRID; do
      if [[ "$RUN_CLASSIC_FLAG" != "0" ]]; then
        run_one "$uin" classic_flag "$flag_every" "$trigger_nmin" ""
      fi
      if [[ "$RUN_GUARD_FLAG" != "0" ]]; then
        run_one "$uin" guard_fixed_flag "$flag_every" "$trigger_nmin" \
          "MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297=1"
      fi
    done
  done
done

python3 scripts/analyze_cuda_resampling_adaptive_flag_0304.py "$RUN_MANIFEST" "$ART_DIR"

echo "[0304-flag] manifest=$RUN_MANIFEST"
echo "[0304-flag] per-run=$ART_DIR/cuda_resampling_adaptive_flag_0304_per_run.csv"
echo "[0304-flag] timeseries=$ART_DIR/cuda_resampling_adaptive_flag_0304_timeseries.csv"
