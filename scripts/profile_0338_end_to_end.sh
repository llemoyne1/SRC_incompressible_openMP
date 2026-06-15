#!/usr/bin/env bash
set -euo pipefail

# 0338 objective profiling harness: no solver modification.
# It compares wall time, CUDA API, GPU kernels, memcpys/syncs, OS runtime and I/O
# for the monolithic CUDA VK binary, SRC_GPU, and SRC_GPU-VIZ.
#
# Typical use from anywhere:
#   SRC_GPU_ROOT=/mnt/e/SRC_MPCD_DEV/SRC_GPU \
#   SRC_GPU_VIZ_ROOT=/mnt/e/SRC_MPCD_DEV/SRC_GPU-VIZ \
#   bash scripts/profile_0338_end_to_end.sh

SRC_GPU_ROOT="${SRC_GPU_ROOT:-/mnt/e/SRC_MPCD_DEV/SRC_GPU}"
SRC_GPU_VIZ_ROOT="${SRC_GPU_VIZ_ROOT:-/mnt/e/SRC_MPCD_DEV/SRC_GPU-VIZ}"
OUT_ROOT="${OUT_ROOT:-${SRC_GPU_ROOT}/runs/profile_0338}"

NX="${NX:-640}"
NY="${NY:-640}"
LX="${LX:-0.8}"
LY="${LY:-0.4}"
U0="${U0:-0.45}"
KBT="${KBT:-0.5}"
DT="${DT:-0.0005}"
XC="${XC:-0.1}"
STEPS="${STEPS:-500}"
SUMMARY_EVERY="${SUMMARY_EVERY:-1000}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-1000}"
DUMP_STRIDE="${DUMP_STRIDE:-1000}"
LOG_STRIDE="${LOG_STRIDE:-1000}"
GAMMA="${GAMMA:-6}"

# Binary/script names can be overridden from the environment.
MONO_BIN="${MONO_BIN:-./build/mpcd_vkkh_play_timed_0333}"
MONO_EXTRA_ARGS="${MONO_EXTRA_ARGS:-}"
SRC_GPU_BIN="${SRC_GPU_BIN:-build/src_mpcd_base_cuda_0334a}"
SRC_GPU_SCRIPT="${SRC_GPU_SCRIPT:-scripts/run_portable_von_karman_resampling_0315.sh}"
SRC_GPU_VIZ_BIN="${SRC_GPU_VIZ_BIN:-build/src_mpcd_base_cuda_livevis_0337d}"
SRC_GPU_VIZ_SCRIPT="${SRC_GPU_VIZ_SCRIPT:-scripts/run_portable_von_karman_resampling_0337_livevis_classic.sh}"

RUN_TIME_V="${RUN_TIME_V:-1}"
RUN_NSYS="${RUN_NSYS:-1}"
RUN_STRACE="${RUN_STRACE:-1}"
RUN_PERF_STAT="${RUN_PERF_STAT:-0}"
INCLUDE_VIZ_IO_AS_OBSERVED="${INCLUDE_VIZ_IO_AS_OBSERVED:-1}"

# Keep the wrapper quiet enough that stdout/logging itself is measured but not amplified by tee.
LIVE_PROGRESS="${LIVE_PROGRESS:-0}"
COMMON_THREADS="${COMMON_THREADS:-8}"
VIZ_THREADS="${VIZ_THREADS:-12}"

mkdir -p "$OUT_ROOT"
OUT_ROOT="$(cd "$OUT_ROOT" && pwd)"
STAMP="$(date +%Y%m%d_%H%M%S)"
SESSION_DIR="$OUT_ROOT/session_${STAMP}"
mkdir -p "$SESSION_DIR"

FILTER_RE='^(MPCD_|SRC_|LIVE_|OMP_|CUDA_)'
NSYS_REPORTS=(summary cuda_api_sum cuda_gpu_kern_sum cuda_gpu_mem_time_sum osrt_sum)

have_cmd() { command -v "$1" >/dev/null 2>&1; }
bool_true() { case "${1:-0}" in 1|true|TRUE|yes|YES|on|ON) return 0;; *) return 1;; esac; }

write_host_manifest() {
  {
    echo "timestamp=${STAMP}"
    echo "hostname=$(hostname)"
    echo "user=$(id -un)"
    echo "kernel=$(uname -a)"
    echo "SRC_GPU_ROOT=${SRC_GPU_ROOT}"
    echo "SRC_GPU_VIZ_ROOT=${SRC_GPU_VIZ_ROOT}"
    echo "OUT_ROOT=${OUT_ROOT}"
    echo "NX=${NX} NY=${NY} LX=${LX} LY=${LY} GAMMA=${GAMMA} STEPS=${STEPS} DT=${DT} KBT=${KBT} U0=${U0}"
    echo "RUN_TIME_V=${RUN_TIME_V} RUN_NSYS=${RUN_NSYS} RUN_STRACE=${RUN_STRACE} RUN_PERF_STAT=${RUN_PERF_STAT}"
    echo "nsys=$(command -v nsys || true)"
    echo "strace=$(command -v strace || true)"
    echo "perf=$(command -v perf || true)"
    echo "nvidia_smi=$(command -v nvidia-smi || true)"
  } > "$SESSION_DIR/host_manifest.txt"
  if have_cmd nvidia-smi; then
    nvidia-smi > "$SESSION_DIR/nvidia_smi.txt" 2>&1 || true
  fi
}

write_common_case_header() {
  local case_dir="$1" root="$2"
  cat <<HEADER_EOF
#!/usr/bin/env bash
set -euo pipefail
CASE_DIR='$case_dir'
cd '$root'
mkdir -p "\$CASE_DIR"
echo "[0338] cwd=\$(pwd)"
echo "[0338] command_start=\$(date --iso-8601=seconds)"
(env | sort | grep -E '$FILTER_RE' || true) > "\$CASE_DIR/env.filtered"
(git rev-parse --abbrev-ref HEAD && git rev-parse HEAD && git describe --tags --always --dirty && git status --short) > "\$CASE_DIR/git.txt" 2>&1 || true
{ ls -lh build/* 2>/dev/null || true; } > "\$CASE_DIR/build_ls.txt"
HEADER_EOF
}

write_mono_cmd() {
  local pass_dir="$1"
  local cmd="$pass_dir/cmd.sh"
  mkdir -p "$pass_dir"
  {
    write_common_case_header "$pass_dir" "$SRC_GPU_ROOT"
    cat <<MONO_EOF
rm -rf vk3_Re300_C || true
if [[ ! -x '$MONO_BIN' ]]; then
  echo '[0338] missing monolithic binary: $MONO_BIN' >&2
  exit 127
fi
cat > "\$CASE_DIR/exact_command.txt" <<'CMDEOF'
$MONO_BIN --Nx $NX --Lx $LX --Ny $NY --U0 $U0 --kBT $KBT --dt $DT --xc $XC --steps $STEPS --dumpStride $DUMP_STRIDE --logStride $LOG_STRIDE $MONO_EXTRA_ARGS
CMDEOF
$MONO_BIN --Nx '$NX' --Lx '$LX' --Ny '$NY' --U0 '$U0' --kBT '$KBT' --dt '$DT' --xc '$XC' --steps '$STEPS' --dumpStride '$DUMP_STRIDE' --logStride '$LOG_STRIDE' $MONO_EXTRA_ARGS
find vk3_Re300_C -maxdepth 3 -type f 2>/dev/null | sort > "\$CASE_DIR/generated_files.txt" || true
echo "[0338] command_end=\$(date --iso-8601=seconds)"
MONO_EOF
  } > "$cmd"
  chmod +x "$cmd"
}

write_src_cmd() {
  local pass_dir="$1" root="$2" script="$3" bin="$4" label="$5" vk_mode="$6" threads="$7" live_enable="$8" live_cuda_field="$9"
  local cmd="$pass_dir/cmd.sh"
  local run_root="$pass_dir/run"
  mkdir -p "$pass_dir"
  {
    write_common_case_header "$pass_dir" "$root"
    cat <<SRC_EOF
if [[ ! -f '$script' ]]; then
  echo '[0338] missing wrapper script: $script' >&2
  exit 127
fi
if [[ ! -x '$bin' ]]; then
  echo '[0338] missing SRC binary: $bin' >&2
  exit 127
fi
export BIN='$bin'
export AUTO_BUILD=0
export FORCE_REBUILD=0
export RUN_MODES=classic
export VK_MODE='$vk_mode'
export BASE_RUN_ROOT='$run_root'
export CLEAN_RUN_ROOT=1
export LIVE_PROGRESS='$LIVE_PROGRESS'
export THREADS='$threads'
export OMP_NUM_THREADS='$threads'
export OMP_PROC_BIND=close
export OMP_PLACES=cores
export OMP_DYNAMIC=false
export NX='$NX'
export NY='$NY'
export Lx='$LX'
export Ly='$LY'
export GAMMA='$GAMMA'
export STEPS='$STEPS'
export DT='$DT'
export KBT='$KBT'
export UIN='$U0'
export UINIT='$U0'
export SUMMARY_EVERY='$SUMMARY_EVERY'
export DUMP_STATE_EVERY='$DUMP_STATE_EVERY'
export INACTIVE_SLOTS=0
export DUMP_ROLE_FILTER=fluid
export SUMMARY_ROLE_FILTER=fluid
export LIVE_VIS_ENABLE='$live_enable'
export LIVE_VIS_CUDA_FIELD='$live_cuda_field'
export LIVE_VIS_RESAMPLING_HOST_MIRROR=0
export LIVE_VIS_FORCE_HOST_MIRROR=0
export SRC_LIVE_VIS_ENABLE='$live_enable'
export SRC_LIVE_VIS_CUDA_FIELD='$live_cuda_field'
export SRC_LIVE_VIS_RESAMPLING_HOST_MIRROR=0
export SRC_LIVE_VIS_FORCE_HOST_MIRROR=0
(env | sort | grep -E '$FILTER_RE' || true) > "\$CASE_DIR/env.effective_before_wrapper"
cat > "\$CASE_DIR/exact_command.txt" <<'CMDEOF'
BIN=$bin AUTO_BUILD=0 RUN_MODES=classic VK_MODE=$vk_mode BASE_RUN_ROOT=$run_root CLEAN_RUN_ROOT=1 THREADS=$threads NX=$NX NY=$NY GAMMA=$GAMMA STEPS=$STEPS bash $script
CMDEOF
bash '$script'
find '$run_root' -maxdepth 6 -type f | sort > "\$CASE_DIR/generated_files.txt" || true
find '$run_root' -maxdepth 6 \( -name '*.kv' -o -name 'environment_*.env' -o -name '*.time' -o -name '*.log' \) -type f -print -exec sh -c 'echo "----- {}"; sed -n "1,220p" "{}"' \; > "\$CASE_DIR/key_generated_texts.txt" 2>&1 || true
echo "[0338] command_end=\$(date --iso-8601=seconds)"
SRC_EOF
  } > "$cmd"
  chmod +x "$cmd"
}

run_time_v() {
  local label="$1" pass_dir="$2"
  echo "[0338] time -v: $label"
  /usr/bin/time -v -o "$pass_dir/time_v.txt" bash "$pass_dir/cmd.sh" > "$pass_dir/stdout.txt" 2> "$pass_dir/stderr.txt" || {
    echo "[0338] ERROR in time -v case $label" >&2
    tail -80 "$pass_dir/stdout.txt" >&2 || true
    tail -80 "$pass_dir/stderr.txt" >&2 || true
    return 1
  }
}

run_nsys() {
  local label="$1" pass_dir="$2"
  if ! have_cmd nsys; then
    echo "[0338] nsys not found; skipping $label" | tee "$pass_dir/nsys_skipped.txt"
    return 0
  fi
  echo "[0338] nsys profile: $label"
  local outbase="$pass_dir/nsys/${label}"
  mkdir -p "$pass_dir/nsys"
  nsys profile --trace=cuda,osrt,nvtx --sample=cpu --force-overwrite=true --output "$outbase" \
    bash "$pass_dir/cmd.sh" > "$pass_dir/nsys/stdout.txt" 2> "$pass_dir/nsys/stderr.txt" || {
      echo "[0338] ERROR in nsys profile case $label" >&2
      tail -80 "$pass_dir/nsys/stderr.txt" >&2 || true
      return 1
    }
  local rep="${outbase}.nsys-rep"
  for report in "${NSYS_REPORTS[@]}"; do
    nsys stats --force-export=true --report "$report" --format csv "$rep" \
      > "$pass_dir/nsys/${report}.csv" 2> "$pass_dir/nsys/${report}.stderr" || true
  done
}

run_strace() {
  local label="$1" pass_dir="$2"
  if ! have_cmd strace; then
    echo "[0338] strace not found; skipping $label" | tee "$pass_dir/strace_skipped.txt"
    return 0
  fi
  echo "[0338] strace -f -c: $label"
  strace -f -c -o "$pass_dir/strace_c.txt" bash "$pass_dir/cmd.sh" \
    > "$pass_dir/strace_stdout.txt" 2> "$pass_dir/strace_stderr.txt" || {
      echo "[0338] ERROR in strace case $label" >&2
      tail -80 "$pass_dir/strace_stderr.txt" >&2 || true
      return 1
    }
}

run_perf_stat() {
  local label="$1" pass_dir="$2"
  if ! have_cmd perf; then
    echo "[0338] perf not found; skipping $label" | tee "$pass_dir/perf_skipped.txt"
    return 0
  fi
  echo "[0338] perf stat: $label"
  perf stat -d -d -d -o "$pass_dir/perf_stat.txt" bash "$pass_dir/cmd.sh" \
    > "$pass_dir/perf_stdout.txt" 2> "$pass_dir/perf_stderr.txt" || true
}

prepare_case_cmd() {
  local label="$1" pass_dir="$2"
  case "$label" in
    mono)
      write_mono_cmd "$pass_dir" ;;
    src_gpu_periodic)
      write_src_cmd "$pass_dir" "$SRC_GPU_ROOT" "$SRC_GPU_SCRIPT" "$SRC_GPU_BIN" "$label" periodic "$COMMON_THREADS" 0 0 ;;
    src_gpu_viz_periodic_live)
      write_src_cmd "$pass_dir" "$SRC_GPU_VIZ_ROOT" "$SRC_GPU_VIZ_SCRIPT" "$SRC_GPU_VIZ_BIN" "$label" periodic "$VIZ_THREADS" 1 1 ;;
    src_gpu_viz_io_live_observed)
      write_src_cmd "$pass_dir" "$SRC_GPU_VIZ_ROOT" "$SRC_GPU_VIZ_SCRIPT" "$SRC_GPU_VIZ_BIN" "$label" io "$VIZ_THREADS" 1 1 ;;
    *)
      echo "Unknown case label: $label" >&2; exit 2 ;;
  esac
}

run_case_all_tools() {
  local label="$1"
  local case_dir="$SESSION_DIR/$label"
  mkdir -p "$case_dir"
  if bool_true "$RUN_TIME_V"; then
    local d="$case_dir/time_v"; prepare_case_cmd "$label" "$d"; run_time_v "$label" "$d"
  fi
  if bool_true "$RUN_NSYS"; then
    local d="$case_dir/nsys_run"; prepare_case_cmd "$label" "$d"; run_nsys "$label" "$d"
  fi
  if bool_true "$RUN_STRACE"; then
    local d="$case_dir/strace"; prepare_case_cmd "$label" "$d"; run_strace "$label" "$d"
  fi
  if bool_true "$RUN_PERF_STAT"; then
    local d="$case_dir/perf"; prepare_case_cmd "$label" "$d"; run_perf_stat "$label" "$d"
  fi
}

write_host_manifest

CASES=(mono src_gpu_periodic src_gpu_viz_periodic_live)
if bool_true "$INCLUDE_VIZ_IO_AS_OBSERVED"; then
  CASES+=(src_gpu_viz_io_live_observed)
fi

printf '%s\n' "${CASES[@]}" > "$SESSION_DIR/cases.txt"
for case_name in "${CASES[@]}"; do
  run_case_all_tools "$case_name"
done

{
  echo "0338 profiling session: $SESSION_DIR"
  echo
  echo "Files to inspect/transmit:"
  find "$SESSION_DIR" -maxdepth 4 -type f \
    \( -name 'time_v.txt' -o -name 'env*.filtered' -o -name 'env.effective_before_wrapper' -o -name 'git.txt' -o -name 'exact_command.txt' -o -name 'generated_files.txt' -o -name 'key_generated_texts.txt' -o -name 'strace_c.txt' -o -name '*.csv' -o -name '*.stderr' -o -name 'stdout.txt' -o -name 'stderr.txt' -o -name 'nvidia_smi.txt' -o -name 'host_manifest.txt' \) | sort
} | tee "$SESSION_DIR/TRANSMIT_THESE_FILES.txt"

echo "[0338] done: $SESSION_DIR"
echo "[0338] transmit $SESSION_DIR/TRANSMIT_THESE_FILES.txt plus the listed files."
