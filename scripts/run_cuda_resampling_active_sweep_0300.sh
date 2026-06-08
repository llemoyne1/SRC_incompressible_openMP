#!/usr/bin/env bash
set -euo pipefail

# 0300 — physical active-validation sweep for post-SRC CUDA resampling.
#
# This script does not use strict OFF/ON equality as the active criterion: an
# active population guard is expected to change the discrete representation.  It
# instead runs a compact matrix of cases/modes and aggregates support-control
# diagnostics plus final physical summaries.
#
# Default cases: TG, Poiseuille, backward step, U-box segmented.  Von Karman is
# optional and uses scripts/run_cuda_resampling_von_karman_validation_0300.sh,
# not the user-editable 0285 demo script.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BIN=${BIN:-build/src_mpcd_base_cuda_0300}
ART_DIR=${ART_DIR:-dev_history/artifacts/gpu_cuda_resampling_active_sweep_0300}
NX=${NX:-64}
NY=${NY:-64}
GAMMA=${GAMMA:-20}
STEPS=${STEPS:-80}
THREADS=${THREADS:-8}
SUMMARY_EVERY=${SUMMARY_EVERY:-$STEPS}
DUMP_STATE_EVERY=${DUMP_STATE_EVERY:-$STEPS}
LIVE_PROGRESS=${LIVE_PROGRESS:-0}
CLEAN_RUN_ROOT=${CLEAN_RUN_ROOT:-1}
FORCE_REBUILD=${FORCE_REBUILD:-1}
STOP_ON_FAIL=${STOP_ON_FAIL:-1}

RUN_TG=${RUN_TG:-1}
RUN_POISEUILLE=${RUN_POISEUILLE:-1}
RUN_STEP=${RUN_STEP:-1}
RUN_SEGMENTED=${RUN_SEGMENTED:-1}
RUN_VK=${RUN_VK:-0}

RECONDITION_EVERY=${RECONDITION_EVERY:-20}
RECONDITION_STRENGTH=${RECONDITION_STRENGTH:-1.0}
GUARD_EVERY=${GUARD_EVERY:-20}
# Format: "NMIN:NTARGET:NMAX ..."
GUARD_GRID=${GUARD_GRID:-"8:20:36 10:20:34 12:20:32"}
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

SEGMENTED_OUTLET_MODE=${SEGMENTED_OUTLET_MODE:-neumann}
VK_UIN=${VK_UIN:-0.30}
VK_OUTLET_MODE=${VK_OUTLET_MODE:-equilibrium_flux}
VK_THERMOSTAT_ENABLE=${VK_THERMOSTAT_ENABLE:-0}
VK_INACTIVE_SLOTS=${VK_INACTIVE_SLOTS:-$((GAMMA * NY * 32))}

mkdir -p "$ART_DIR"

if [[ "$FORCE_REBUILD" != "0" && "$FORCE_REBUILD" != "false" && "$FORCE_REBUILD" != "FALSE" ]]; then
  echo "[0300-sweep] rebuilding $BIN"
  OUT="$BIN" CUDA_ARCH_FLAGS="${CUDA_ARCH_FLAGS:-}" bash scripts/build_src_mpcd_cuda_0300.sh
elif [[ ! -x "$BIN" ]]; then
  OUT="$BIN" CUDA_ARCH_FLAGS="${CUDA_ARCH_FLAGS:-}" bash scripts/build_src_mpcd_cuda_0300.sh
fi
if [[ ! -x "$BIN" ]]; then
  echo "[0300-sweep] ERROR: missing binary $BIN" >&2
  exit 127
fi

RUN_MANIFEST=${RUN_MANIFEST:-$ART_DIR/cuda_resampling_active_sweep_0300_run_manifest.csv}
printf 'caseName,modeName,nmin,ntarget,nmax,runRoot,exitCode,script,extraEnv\n' > "$RUN_MANIFEST"

append_manifest() {
  python3 - "$RUN_MANIFEST" "$@" <<'PY'
import csv, sys
out=sys.argv[1]
with open(out, 'a', newline='') as fh:
    csv.writer(fh).writerow(sys.argv[2:])
PY
}

run_one() {
  local case_name=$1 script=$2 mode_name=$3 nmin=$4 ntarget=$5 nmax=$6 extra_env=${7:-}
  local run_root="$ART_DIR/$case_name/$mode_name"
  echo "[0300-sweep] running case=$case_name mode=$mode_name script=$script"
  mkdir -p "$(dirname "$run_root")"
  local rc=0
  set +e
  env BIN="$BIN" AUTO_BUILD=0 LIVE_PROGRESS="$LIVE_PROGRESS" CLEAN_RUN_ROOT="$CLEAN_RUN_ROOT" \
      NX="$NX" NY="$NY" GAMMA="$GAMMA" STEPS="$STEPS" SUMMARY_EVERY="$SUMMARY_EVERY" DUMP_STATE_EVERY="$DUMP_STATE_EVERY" \
      THREADS="$THREADS" RUN_ROOT="$run_root" \
      MPCD_CUDA_RESAMPLING_SUPPORT_SURVEY_0295=0 \
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
  append_manifest "$case_name" "$mode_name" "$nmin" "$ntarget" "$nmax" "$run_root" "$rc" "$script" "$extra_env"
  if [[ "$rc" != "0" ]]; then
    echo "[0300-sweep] FAIL case=$case_name mode=$mode_name rc=$rc" >&2
    echo "[0300-sweep] stdout/stderr: $run_root.stdout.log $run_root.stderr.log" >&2
    if [[ "$STOP_ON_FAIL" == "1" ]]; then
      exit "$rc"
    fi
  fi
}

run_case_matrix() {
  local case_name=$1 script=$2 extra_env=${3:-}
  run_one "$case_name" "$script" classic 0 0 0 "$extra_env"
  run_one "$case_name" "$script" mass0296 0 0 0 "MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296=1 $extra_env"
  local triple nmin ntarget nmax label mass_guard_flag
  for triple in $GUARD_GRID; do
    IFS=: read -r nmin ntarget nmax <<<"$triple"
    label="guard0299_nmin${nmin}_nt${ntarget}_nmax${nmax}"
    mass_guard_flag="MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296=$GUARD_WITH_MASS_RECONDITION"
    run_one "$case_name" "$script" "$label" "$nmin" "$ntarget" "$nmax" "$mass_guard_flag MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297=1 $extra_env"
  done
}

if [[ "$RUN_TG" != "0" ]]; then
  run_case_matrix tg_periodic scripts/run_demo_src_classic_cuda_taylor_green_forced_0283.sh ""
fi
if [[ "$RUN_POISEUILLE" != "0" ]]; then
  run_case_matrix poiseuille_wall scripts/run_demo_src_classic_cuda_poiseuille_periodic_forced_0283.sh ""
fi
if [[ "$RUN_STEP" != "0" ]]; then
  run_case_matrix backward_step_io scripts/run_demo_src_classic_cuda_backward_step_io_0283.sh ""
fi
if [[ "$RUN_SEGMENTED" != "0" ]]; then
  run_case_matrix segmented_box_same_face scripts/run_demo_src_classic_cuda_box_same_face_io_0283.sh "OUTLET_MODE=$SEGMENTED_OUTLET_MODE"
fi
if [[ "$RUN_VK" != "0" ]]; then
  run_case_matrix von_karman_circle_io scripts/run_cuda_resampling_von_karman_validation_0300.sh "UIN=$VK_UIN OUTLET_MODE=$VK_OUTLET_MODE THERMOSTAT_ENABLE=$VK_THERMOSTAT_ENABLE INACTIVE_SLOTS=$VK_INACTIVE_SLOTS"
fi

python3 scripts/analyze_cuda_resampling_active_sweep_0300.py "$RUN_MANIFEST" "$ART_DIR"

echo "[0300-sweep] manifest=$RUN_MANIFEST"
echo "[0300-sweep] per-run=$ART_DIR/cuda_resampling_active_sweep_0300_per_run.csv"
echo "[0300-sweep] vs-classic=$ART_DIR/cuda_resampling_active_sweep_0300_vs_classic.csv"
