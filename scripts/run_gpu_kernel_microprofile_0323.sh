#!/usr/bin/env bash
set -euo pipefail

# 0323 script-only micro-profiler for the remaining CUDA kernel bottleneck.
# It does not modify or rebuild the solver.  It runs a short SRC/VKKH case
# through Nsight Compute when available, falling back to nvprof if present.

ROOT_DIR="$(pwd)"
ART="${ART:-dev_history/artifacts/gpu_kernel_microprofile_0323}"
STEPS="${STEPS:-300}"
NX="${NX:-192}"
NY="${NY:-64}"
GAMMA="${GAMMA:-20}"
INACTIVE_SLOTS="${INACTIVE_SLOTS:-100000}"
THREADS="${THREADS:-8}"
SRC_BIN="${SRC_BIN:-build/src_mpcd_base_cuda_0315m_profile}"
VKKH_BIN="${VKKH_BIN:-build/mpcd_vkkh_play_0317c}"
RUN_SRC_PERIODIC="${RUN_SRC_PERIODIC:-1}"
RUN_VKKH="${RUN_VKKH:-1}"
NCU_LAUNCH_SKIP="${NCU_LAUNCH_SKIP:-20}"
NCU_LAUNCH_COUNT="${NCU_LAUNCH_COUNT:-400}"
NCU_METRICS="${NCU_METRICS:-gpu__time_duration.sum}"

mkdir -p "$ART" "$ART/logs" "$ART/raw" "$ART/time" "$ART/runs"

MANIFEST="$ART/gpu_kernel_microprofile_0323_manifest.csv"
echo "target,profiler,steps,nx,ny,gamma,binary,runRoot,rawFile,timeFile,stdoutFile,stderrFile,exitCode,note" > "$MANIFEST"

run_with_profiler() {
  local target="$1"
  local run_script="$2"
  local run_root="$3"
  local binary="$4"
  local raw="$ART/raw/${target}.csv"
  local time_file="$ART/time/${target}.time.csv"
  local stdout_log="$ART/logs/${target}.stdout.log"
  local stderr_log="$ART/logs/${target}.stderr.log"
  local profiler="time_only"
  local exit_code=0

  echo "[0323-kernel-profile] target=$target steps=$STEPS"
  if command -v ncu >/dev/null 2>&1; then
    profiler="ncu"
    set +e
    /usr/bin/time -f "elapsed_s,%e\nuser_s,%U\nsys_s,%S" -o "$time_file" \
      ncu --target-processes all \
          --kernel-name-base function \
          --csv --page raw \
          --metrics "$NCU_METRICS" \
          --launch-skip "$NCU_LAUNCH_SKIP" \
          --launch-count "$NCU_LAUNCH_COUNT" \
          --log-file "$raw" \
          bash "$run_script" >"$stdout_log" 2>"$stderr_log"
    exit_code=$?
    set -e
  elif command -v nvprof >/dev/null 2>&1; then
    profiler="nvprof"
    set +e
    /usr/bin/time -f "elapsed_s,%e\nuser_s,%U\nsys_s,%S" -o "$time_file" \
      nvprof --print-gpu-trace --csv --log-file "$raw" \
      bash "$run_script" >"$stdout_log" 2>"$stderr_log"
    exit_code=$?
    set -e
  else
    set +e
    /usr/bin/time -f "elapsed_s,%e\nuser_s,%U\nsys_s,%S" -o "$time_file" \
      bash "$run_script" >"$stdout_log" 2>"$stderr_log"
    exit_code=$?
    set -e
    echo "profiler_unavailable,ncu_or_nvprof_not_found" > "$raw"
  fi

  echo "$target,$profiler,$STEPS,$NX,$NY,$GAMMA,$binary,$run_root,$raw,$time_file,$stdout_log,$stderr_log,$exit_code,script_only_kernel_microprofile_0323" >> "$MANIFEST"
}

if [[ "$RUN_SRC_PERIODIC" == "1" ]]; then
  SRC_RUN_ROOT="$ART/runs/src_cuda_v2_0322_periodic"
  SRC_RUN_SCRIPT="$ART/run_src_cuda_v2_0322_periodic.sh"
  cat > "$SRC_RUN_SCRIPT" <<EOF
#!/usr/bin/env bash
set -euo pipefail
cd "$ROOT_DIR"
env BIN="$SRC_BIN" AUTO_BUILD=0 LIVE_PROGRESS=0 CLEAN_RUN_ROOT=1 \\
  RUN_ROOT="$SRC_RUN_ROOT" Lx="3.0" Ly="1.0" NX="$NX" NY="$NY" GAMMA="$GAMMA" STEPS="$STEPS" DT="0.001" KBT="0.001" SEED="1628505" \\
  UIN="0.2" CYLINDER_CX="0.65" CYLINDER_CY="0.50" CYLINDER_R="0.15" \\
  INACTIVE_SLOTS="$INACTIVE_SLOTS" THREADS="$THREADS" \\
  SUMMARY_EVERY=1000000000 DUMP_STATE_EVERY=0 SRC_GPU_DEMO_REQUIRE_DUMPS=0 DUMP_ROLE_FILTER=fluid SUMMARY_ROLE_FILTER=fluid \\
  RESAMPLING_ENABLE=0 RESAMPLING_SURVEY_ENABLE=0 GUARD_EVERY=999999 \\
  MPCD_INTERNAL_PROFILES="0" MPCD_CUDA_RESIDENT_PROFILE_0266="0" \\
  MPCD_CUDA_CLASSIC_SRC_WALL_CIRCLE_RESIDENT_0318=1 \\
  MPCD_CUDA_STREAMING_WALL_SIMPLE_0246=1 \\
  MPCD_CUDA_STREAMING_WALL_SIMPLE_0246_DOWNLOAD_ALL=0 \\
  MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WALL_VP_DIAG_0319=1 \\
  MPCD_CUDA_CLASSIC_SRC_RESIDENT_0271_ASYNC_STREAM=1 \\
  MPCD_CUDA_CLASSIC_SRC_WALL_RESIDENT_0271_FAST_DIAGNOSTICS=1 \\
  MPCD_CUDA_PERSISTENT_SRC_COLLISION_FAST_THERMOSTAT_DIAG_0321=1 \\
  MPCD_CUDA_PERSISTENT_SRC_COLLISION_DEVICE_ROTATION_0272=1 \\
  MPCD_CUDA_PERSISTENT_SRC_COLLISION_LAZY_KERNEL_CHECK_0273=1 \\
  MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_SETUP_SYNC_0273=1 \\
  bash "scripts/run_demo_src_classic_cuda_von_karman_cylinder_0285.sh"
EOF
  chmod +x "$SRC_RUN_SCRIPT"
  run_with_profiler "src_cuda_v2_0322_periodic" "$SRC_RUN_SCRIPT" "$SRC_RUN_ROOT" "$SRC_BIN"
fi

if [[ "$RUN_VKKH" == "1" ]]; then
  VKKH_RUN_ROOT="$ART/runs/mpcd_vkkh_play"
  VKKH_RUN_SCRIPT="$ART/run_mpcd_vkkh_play.sh"
  cat > "$VKKH_RUN_SCRIPT" <<EOF
#!/usr/bin/env bash
set -euo pipefail
cd "$ROOT_DIR"
mkdir -p "$VKKH_RUN_ROOT/output"
"$VKKH_BIN" --mode vk --Nx "$NX" --Ny "$NY" --gamma "$GAMMA" --steps "$STEPS" --out "$VKKH_RUN_ROOT/output"
EOF
  chmod +x "$VKKH_RUN_SCRIPT"
  run_with_profiler "mpcd_vkkh_play" "$VKKH_RUN_SCRIPT" "$VKKH_RUN_ROOT" "$VKKH_BIN"
fi

python3 scripts/summarize_gpu_kernel_microprofile_0323.py "$ART"

echo "[0323-kernel-profile] results: $ART"
