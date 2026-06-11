#!/usr/bin/env bash
set -euo pipefail

# 0326 — script-only non-regression harness for the post-0322 clean CUDA branch.
# Goal: check that Q6, resampling, virial and closed-capacity paths still run
# after the classic CUDA performance work 0318b--0322 and the 0325 rollback.
# This script does not modify the solver and does not build by default.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ART_DIR=${ART_DIR:-dev_history/artifacts/gpu_nonregression_q6_resampling_virial_0326}
CLEAN_ART_DIR=${CLEAN_ART_DIR:-1}
BIN=${BIN:-build/src_mpcd_base_cuda_0315m_profile}
SRC_BUILD=${SRC_BUILD:-0}
SRC_BUILD_SCRIPT=${SRC_BUILD_SCRIPT:-scripts/build_src_mpcd_cuda_0315b.sh}

NX=${NX:-32}
NY=${NY:-32}
GAMMA=${GAMMA:-20}
STEPS=${STEPS:-80}
SUMMARY_EVERY=${SUMMARY_EVERY:-20}
THREADS=${THREADS:-8}
DT=${DT:-0.001}
KBT=${KBT:-0.001}
SEED=${SEED:-1620326}
INACTIVE_SLOTS=${INACTIVE_SLOTS:-100000}

# Set RUN_TARGETS to a subset if needed, e.g.
# RUN_TARGETS="q6_only_tg hybrid_cuda_q6_resampling_tg"
RUN_TARGETS=${RUN_TARGETS:-"q6_only_tg resampling_only_tg hybrid_cuda_q6_resampling_tg hybrid_cuda_piston_virial"}
STOP_ON_FAIL=${STOP_ON_FAIL:-0}
TIME_BIN=${TIME_BIN:-/usr/bin/time}

if [[ "$CLEAN_ART_DIR" == "1" || "$CLEAN_ART_DIR" == "true" || "$CLEAN_ART_DIR" == "TRUE" ]]; then
  rm -rf "$ART_DIR"
fi
mkdir -p "$ART_DIR" "$ART_DIR/logs" "$ART_DIR/time" "$ART_DIR/runs"

if [[ "$SRC_BUILD" == "1" ]]; then
  if [[ ! -f "$SRC_BUILD_SCRIPT" ]]; then
    SRC_BUILD_SCRIPT="scripts/build_src_mpcd_cuda_0293.sh"
  fi
  echo "[0326-nonreg] building SRC binary: $BIN via $SRC_BUILD_SCRIPT"
  OUT="$BIN" CUDA_ARCH_FLAGS="${CUDA_ARCH_FLAGS:-}" bash "$SRC_BUILD_SCRIPT"
fi
if [[ ! -x "$BIN" ]]; then
  echo "[0326-nonreg] ERROR: missing executable BIN=$BIN" >&2
  echo "[0326-nonreg]        Build once or rerun with SRC_BUILD=1." >&2
  exit 127
fi
if [[ ! -f scripts/run_validation_mono_config_0162.sh ]]; then
  echo "[0326-nonreg] ERROR: missing scripts/run_validation_mono_config_0162.sh" >&2
  exit 127
fi

# Record whether the rejected 0325 code is still present in the working tree.
GREP_0325="$ART_DIR/working_tree_0325_grep.txt"
set +e
grep -R "0325\|FUSE_WALL\|fuse_wall_finalize" -n \
  src/cuda_persistent_mpcd_step.cu \
  scripts/run_demo_src_classic_cuda_von_karman_cylinder_0285.sh \
  > "$GREP_0325" 2>&1
grep_rc=$?
set -e
if [[ "$grep_rc" != "0" ]]; then
  echo "working tree OK: no 0325" > "$GREP_0325"
fi
cat "$GREP_0325"

MANIFEST="$ART_DIR/gpu_nonregression_q6_resampling_virial_0326_manifest.csv"
printf 'target,caseList,runRoot,stdoutFile,stderrFile,timeFile,exitCode,note\n' > "$MANIFEST"

append_manifest() {
  python3 - "$MANIFEST" "$@" <<'PY'
import csv, sys
with open(sys.argv[1], 'a', newline='') as f:
    csv.writer(f).writerow(sys.argv[2:])
PY
}

run_with_time() {
  local time_file=$1 stdout_file=$2 stderr_file=$3
  shift 3
  "$TIME_BIN" -f 'elapsed_seconds,%e\nuser_seconds,%U\nsys_seconds,%S\nmax_rss_kb,%M\nexit_code,%x' -o "$time_file" \
    "$@" >"$stdout_file" 2>"$stderr_file"
}

# Conservative CUDA persistent SRC flags used only for hybrid smokes.
# Q6/resampling/virial remain CPU/host modules after the SRC classic CUDA step.
export_cuda_hybrid_flags_0326() {
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_STRICT=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_ACTIVE_STRICT=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_MINIMAL_DOWNLOAD_0257=1
  export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE=1
  export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_STRICT=1
  export MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_FAST_THERMOSTAT_DIAG_0321=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_DEVICE_ROTATION_0272=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_LAZY_KERNEL_CHECK_0273=1
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_SETUP_SYNC_0273=1
  export MPCD_CUDA_PERSISTENT_THREADS_PER_BLOCK="${MPCD_CUDA_PERSISTENT_THREADS_PER_BLOCK:-256}"
  # Explicitly keep the rejected 0325 path disabled if stale code is present.
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_FUSE_WALL_FINALIZE_ROTATION_0325=0
  export MPCD_CUDA_PERSISTENT_SRC_COLLISION_DISABLE_FUSE_WALL_FINALIZE_ROTATION_0325=1
}

clear_cuda_hybrid_flags_0326() {
  unset MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE || true
  unset MPCD_CUDA_PERSISTENT_SRC_COLLISION_STRICT || true
  unset MPCD_CUDA_PERSISTENT_SRC_COLLISION_ACTIVE_STRICT || true
  unset MPCD_CUDA_PERSISTENT_SRC_COLLISION_MINIMAL_DOWNLOAD_0257 || true
  unset MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE || true
  unset MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_STRICT || true
  unset MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260 || true
  unset MPCD_CUDA_PERSISTENT_SRC_COLLISION_FAST_THERMOSTAT_DIAG_0321 || true
  unset MPCD_CUDA_PERSISTENT_SRC_COLLISION_DEVICE_ROTATION_0272 || true
  unset MPCD_CUDA_PERSISTENT_SRC_COLLISION_LAZY_KERNEL_CHECK_0273 || true
  unset MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_SETUP_SYNC_0273 || true
  unset MPCD_CUDA_PERSISTENT_THREADS_PER_BLOCK || true
  unset MPCD_CUDA_PERSISTENT_SRC_COLLISION_FUSE_WALL_FINALIZE_ROTATION_0325 || true
  unset MPCD_CUDA_PERSISTENT_SRC_COLLISION_DISABLE_FUSE_WALL_FINALIZE_ROTATION_0325 || true
}

run_target() {
  local target=$1
  local case_list="tg_periodic_full"
  local projection_enable="true"
  local resampling_enable="false"
  local src_classic_cuda="false"
  local projection_backend="cpu"
  local note=""
  local nx="$NX"
  local ny="$NY"
  local steps="$STEPS"

  case "$target" in
    q6_only_tg)
      case_list="tg_periodic_full"
      projection_enable="true"
      resampling_enable="false"
      src_classic_cuda="false"
      note="CPU SRC + Q6, resampling off"
      ;;
    resampling_only_tg)
      case_list="tg_periodic_full"
      projection_enable="false"
      resampling_enable="true"
      src_classic_cuda="false"
      note="CPU SRC + resampling, Q6 off"
      ;;
    hybrid_cuda_q6_resampling_tg)
      case_list="tg_periodic_full"
      projection_enable="true"
      resampling_enable="true"
      src_classic_cuda="true"
      note="CUDA classic SRC + Q6 + resampling"
      ;;
    hybrid_cuda_piston_virial)
      case_list="piston_virial_full"
      projection_enable="true"
      resampling_enable="true"
      src_classic_cuda="true"
      steps="${PISTON_STEPS:-$STEPS}"
      note="CUDA classic SRC + Q6 + resampling + closed-capacity virial"
      ;;
    *)
      echo "[0326-nonreg] ERROR: unknown target=$target" >&2
      exit 2
      ;;
  esac

  local run_root="$ART_DIR/runs/$target"
  local stdout_file="$ART_DIR/logs/${target}.stdout.log"
  local stderr_file="$ART_DIR/logs/${target}.stderr.log"
  local time_file="$ART_DIR/time/${target}.time.csv"
  mkdir -p "$run_root"

  echo "[0326-nonreg] run target=$target cases=$case_list steps=$steps note=$note"
  if [[ "$src_classic_cuda" == "true" ]]; then
    export_cuda_hybrid_flags_0326
  else
    clear_cuda_hybrid_flags_0326
  fi

  set +e
  run_with_time "$time_file" "$stdout_file" "$stderr_file" \
    env BIN="$BIN" BUILD_IF_MISSING=0 RUN_ROOT="$run_root" RUN_TAG="$target" \
      CASE_LIST="$case_list" NX="$nx" NY="$ny" GAMMA="$GAMMA" STEPS="$steps" \
      SUMMARY_EVERY="$SUMMARY_EVERY" DUMP_STATE_EVERY=0 THREADS="$THREADS" \
      DT="$DT" KBT="$KBT" SEED="$SEED" PROJECTION_BACKEND="$projection_backend" \
      PROJECTION_ENABLE="$projection_enable" RESAMPLING_ENABLE="$resampling_enable" \
      SRC_CLASSIC_CUDA_MODE_ENABLE="$src_classic_cuda" \
      WALL_THERMAL_NOISE=0.0 THERMOSTAT_ENABLE=true \
      RESAMP_N_MIN="${RESAMP_N_MIN:-12}" RESAMP_N_TARGET="${RESAMP_N_TARGET:-20}" RESAMP_N_MAX="${RESAMP_N_MAX:-28}" \
      PISTON_YTOP0="${PISTON_YTOP0:-0.95}" PISTON_YTOP_VELOCITY="${PISTON_YTOP_VELOCITY:--0.002}" \
      CAP_VIRIAL_K="${CAP_VIRIAL_K:-2.0}" CAP_VIRIAL_GAIN="${CAP_VIRIAL_GAIN:-2.0}" \
      CAP_VIRIAL_KICK_STRENGTH="${CAP_VIRIAL_KICK_STRENGTH:-0.05}" \
      bash scripts/run_validation_mono_config_0162.sh
  local rc=$?
  set -e
  clear_cuda_hybrid_flags_0326
  append_manifest "$target" "$case_list" "$run_root" "$stdout_file" "$stderr_file" "$time_file" "$rc" "$note"
  if [[ "$rc" != "0" ]]; then
    echo "[0326-nonreg] WARNING: target=$target failed rc=$rc" >&2
    tail -80 "$stderr_file" >&2 || true
    tail -80 "$stdout_file" >&2 || true
    if [[ "$STOP_ON_FAIL" == "1" ]]; then exit "$rc"; fi
  fi
}

for target in $RUN_TARGETS; do
  run_target "$target"
done

python3 scripts/summarize_gpu_nonregression_q6_resampling_virial_0326.py "$MANIFEST" "$ART_DIR"

echo "[0326-nonreg] manifest: $MANIFEST"
echo "[0326-nonreg] summary : $ART_DIR/gpu_nonregression_q6_resampling_virial_0326_summary.csv"
echo "[0326-nonreg] flags   : $GREP_0325"
