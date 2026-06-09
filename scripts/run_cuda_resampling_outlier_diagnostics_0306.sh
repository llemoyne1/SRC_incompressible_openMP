#!/usr/bin/env bash
set -euo pipefail

# 0306 — velocity-outlier diagnostics.  This script reuses the 0305 post-SRC
# geometry flag path and enables the additional 0306 population-bin / outlier
# columns.  It does not mutate particles beyond the optional resampling mode
# requested for comparison.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BIN=${BIN:-build/src_mpcd_base_cuda_0306}
ART_DIR=${ART_DIR:-dev_history/artifacts/gpu_cuda_resampling_outlier_diagnostics_0306}
FORCE_REBUILD=${FORCE_REBUILD:-1}
STOP_ON_FAIL=${STOP_ON_FAIL:-1}
# Some 0283 demo wrappers fail with rc=2 when summary_runtime.csv is absent even though
# the diagnostic CSV/dumps were produced. 0306 only needs the diagnostic CSV, so accept
# that condition by default.
ALLOW_DIAG_ONLY_SUCCESS=${ALLOW_DIAG_ONLY_SUCCESS:-1}
LIVE_PROGRESS=${LIVE_PROGRESS:-0}
CLEAN_RUN_ROOT=${CLEAN_RUN_ROOT:-1}
THREADS=${THREADS:-8}
GAMMA=${GAMMA:-20}
KBT=${KBT:-0.001}
FLAG_EVERY=${FLAG_EVERY:-10}
TRIGGER_NMIN=${TRIGGER_NMIN:-6}
TRIGGER_EMPTY=${TRIGGER_EMPTY:-1}
HIGH_U=${HIGH_U:-1.0}
OUTLIER_U=${OUTLIER_U:-$HIGH_U}
SUMMARY_EVERY=${SUMMARY_EVERY:-100}
DUMP_STATE_EVERY=${DUMP_STATE_EVERY:-500}

RUN_CLASSIC=${RUN_CLASSIC:-1}
RUN_RESAMPLING=${RUN_RESAMPLING:-1}
RUN_STEP=${RUN_STEP:-1}
RUN_VK=${RUN_VK:-1}
RUN_TG_HOLE=${RUN_TG_HOLE:-1}
RUN_POISEUILLE=${RUN_POISEUILLE:-0}

# Defaults are intentionally more discriminating than 0305 but still moderate.
STEP_NX=${STEP_NX:-128}; STEP_NY=${STEP_NY:-48}; STEP_STEPS=${STEP_STEPS:-6000}; STEP_DT=${STEP_DT:-0.0008}; STEP_UIN=${STEP_UIN:-0.60}
VK_NX=${VK_NX:-128}; VK_NY=${VK_NY:-48}; VK_STEPS=${VK_STEPS:-6000}; VK_DT=${VK_DT:-0.0005}; VK_UIN=${VK_UIN:-0.45}; VK_THERMOSTAT_ENABLE=${VK_THERMOSTAT_ENABLE:-1}
TG_NX=${TG_NX:-64}; TG_NY=${TG_NY:-64}; TG_STEPS=${TG_STEPS:-2000}; TG_DT=${TG_DT:-0.001}
POISEUILLE_NX=${POISEUILLE_NX:-96}; POISEUILLE_NY=${POISEUILLE_NY:-48}; POISEUILLE_STEPS=${POISEUILLE_STEPS:-3000}; POISEUILLE_DT=${POISEUILLE_DT:-0.001}; POISEUILLE_BODY_AX=${POISEUILLE_BODY_AX:-0.01}

GUARD_NMIN=${GUARD_NMIN:-12}
GUARD_NTARGET=${GUARD_NTARGET:-20}
GUARD_NMAX=${GUARD_NMAX:-32}
GUARD_EVERY=${GUARD_EVERY:-1}
RESTORE_ENABLE=${RESTORE_ENABLE:-1}
BOUNDARY_AWARE=${BOUNDARY_AWARE:-1}
OPEN_BOUNDARY_HALO_CELLS=${OPEN_BOUNDARY_HALO_CELLS:-1}

mkdir -p "$ART_DIR"

if [[ "$FORCE_REBUILD" != "0" && "$FORCE_REBUILD" != "false" && "$FORCE_REBUILD" != "FALSE" ]]; then
  OUT="$BIN" CUDA_ARCH_FLAGS="${CUDA_ARCH_FLAGS:-}" bash scripts/build_src_mpcd_cuda_0306.sh
elif [[ ! -x "$BIN" ]]; then
  OUT="$BIN" CUDA_ARCH_FLAGS="${CUDA_ARCH_FLAGS:-}" bash scripts/build_src_mpcd_cuda_0306.sh
fi

RUN_MANIFEST=${RUN_MANIFEST:-$ART_DIR/cuda_resampling_outlier_diagnostics_0306_run_manifest.csv}
printf 'caseName,modeName,runRoot,exitCode,script,extraEnv\n' > "$RUN_MANIFEST"

append_manifest() {
  python3 - "$RUN_MANIFEST" "$@" <<'PY'
import csv, sys
with open(sys.argv[1], 'a', newline='') as fh:
    csv.writer(fh).writerow(sys.argv[2:])
PY
}

common_env=(
  BIN="$BIN" AUTO_BUILD=0 LIVE_PROGRESS="$LIVE_PROGRESS" CLEAN_RUN_ROOT="$CLEAN_RUN_ROOT" THREADS="$THREADS"
  GAMMA="$GAMMA" KBT="$KBT" SUMMARY_EVERY="$SUMMARY_EVERY" DUMP_STATE_EVERY="$DUMP_STATE_EVERY"
  MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304=1
  MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304_EVERY="$FLAG_EVERY"
  MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304_TRIGGER_NMIN="$TRIGGER_NMIN"
  MPCD_CUDA_RESAMPLING_ADAPTIVE_FLAG_0304_TRIGGER_EMPTY="$TRIGGER_EMPTY"
  MPCD_CUDA_RESAMPLING_GEOMETRY_DIAG_0305_HIGH_U="$HIGH_U"
  MPCD_CUDA_RESAMPLING_OUTLIER_0306_U_THRESHOLD="$OUTLIER_U"
  GUARD_NMIN="$GUARD_NMIN" GUARD_NTARGET="$GUARD_NTARGET" GUARD_NMAX="$GUARD_NMAX" GUARD_EVERY="$GUARD_EVERY"
  RESTORE_ENABLE="$RESTORE_ENABLE" BOUNDARY_AWARE="$BOUNDARY_AWARE" OPEN_BOUNDARY_HALO_CELLS="$OPEN_BOUNDARY_HALO_CELLS"
)

run_one() {
  local case_name=$1 mode_name=$2 script=$3 run_root=$4; shift 4
  echo "[0306-outlier] running case=$case_name mode=$mode_name script=$script"
  mkdir -p "$(dirname "$run_root")"
  local stdout_log="${run_root}.stdout.log"
  local stderr_log="${run_root}.stderr.log"
  local rc=0
  set +e
  env "${common_env[@]}" "$@" RUN_ROOT="$run_root" bash "$script" >"$stdout_log" 2>"$stderr_log"
  rc=$?
  set -e

  # 0306 is a diagnostic run.  Some legacy demo wrappers require
  # output/summary_runtime.csv and return rc=2 if it is missing, even when the
  # binary completed and produced the diagnostic CSV and state dumps.  In that
  # case, accept the run so the analyzer can use cuda_resampling_adaptive_flag_0304.csv.
  local effective_rc="$rc"
  local diag_csv="$run_root/output/cuda_resampling_adaptive_flag_0304.csv"
  local dump_count=0
  if [[ -d "$run_root/output" ]]; then
    dump_count=$(find "$run_root/output" -maxdepth 1 -name 'state_step_*.smpcd' -type f | wc -l | tr -d ' ')
  fi
  if [[ "$rc" != "0" && "$ALLOW_DIAG_ONLY_SUCCESS" != "0" && -s "$diag_csv" && "$dump_count" != "0" ]]; then
    echo "[0306-outlier] WARNING: accepting diagnostic-only run case=$case_name mode=$mode_name wrapperRc=$rc diagCsv=$diag_csv dumps=$dump_count" >&2
    effective_rc=0
  fi

  append_manifest "$case_name" "$mode_name" "$run_root" "$effective_rc" "$script" "$* wrapperRc=$rc diagCsv=$diag_csv dumps=$dump_count"
  if [[ "$effective_rc" != "0" ]]; then
    echo "[0306-outlier] FAIL case=$case_name mode=$mode_name rc=$rc" >&2
    echo "[0306-outlier] stdout/stderr: $stdout_log $stderr_log" >&2
    if [[ "$STOP_ON_FAIL" == "1" ]]; then exit "$rc"; fi
  fi
}

run_case_modes() {
  local case_name=$1 script=$2 root_base=$3; shift 3
  if [[ "$RUN_CLASSIC" != "0" ]]; then
    run_one "$case_name" classic_flag "$script" "$root_base/classic_flag" RESAMPLING_ENABLE=0 "$@"
  fi
  if [[ "$RUN_RESAMPLING" != "0" ]]; then
    run_one "$case_name" resampling_guard "$script" "$root_base/resampling_guard_nmin${GUARD_NMIN}_nt${GUARD_NTARGET}_nmax${GUARD_NMAX}" RESAMPLING_ENABLE=1 "$@"
  fi
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

if [[ "$RUN_POISEUILLE" != "0" ]]; then
  run_case_modes poiseuille_wall "scripts/run_demo_src_classic_cuda_poiseuille_periodic_forced_0283.sh" "$ART_DIR/poiseuille_wall" \
    NX="$POISEUILLE_NX" NY="$POISEUILLE_NY" STEPS="$POISEUILLE_STEPS" DT="$POISEUILLE_DT" BODY_AX="$POISEUILLE_BODY_AX"
fi

python3 scripts/analyze_cuda_resampling_outlier_diagnostics_0306.py "$RUN_MANIFEST" "$ART_DIR"

echo "[0306-outlier] manifest=$RUN_MANIFEST"
echo "[0306-outlier] per-run=$ART_DIR/cuda_resampling_outlier_diagnostics_0306_per_run.csv"
echo "[0306-outlier] timeseries=$ART_DIR/cuda_resampling_outlier_diagnostics_0306_timeseries.csv"
echo "[0306-outlier] worst=$ART_DIR/cuda_resampling_outlier_diagnostics_0306_worst_cells.csv"
