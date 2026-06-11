#!/usr/bin/env bash
set -euo pipefail

# 0317b — objective GPU profiling harness, script-only.
# This supersedes 0317 by fixing Nsight Systems option compatibility and by
# falling back cleanly to /usr/bin/time if Nsight fails. No solver source is
# modified.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ART_DIR=${ART_DIR:-dev_history/artifacts/gpu_objective_profile_0317b}
CLEAN_ART_DIR=${CLEAN_ART_DIR:-1}
RUN_SRC=${RUN_SRC:-1}
RUN_VKKH=${RUN_VKKH:-1}
WARMUP=${WARMUP:-1}
REPEATS=${REPEATS:-1}

# Comparable VK defaults. Override from the shell if needed.
Lx=${Lx:-3.0}; Ly=${Ly:-1.0}; NX=${NX:-192}; NY=${NY:-64}; GAMMA=${GAMMA:-20}
STEPS=${STEPS:-10000}; DT=${DT:-0.001}; KBT=${KBT:-0.001}; UIN=${UIN:-0.2}; SEED=${SEED:-1628505}
CYLINDER_CX=${CYLINDER_CX:-0.65}; CYLINDER_CY=${CYLINDER_CY:-0.50}; CYLINDER_R=${CYLINDER_R:-0.15}
THREADS=${THREADS:-8}; INACTIVE_SLOTS=${INACTIVE_SLOTS:-100000}

SRC_BIN=${SRC_BIN:-build/src_mpcd_base_cuda_0315m_profile}
SRC_BUILD=${SRC_BUILD:-1}
SRC_BUILD_SCRIPT=${SRC_BUILD_SCRIPT:-scripts/build_src_mpcd_cuda_0315b.sh}
SRC_RUN_SCRIPT=${SRC_RUN_SCRIPT:-scripts/run_demo_src_classic_cuda_von_karman_cylinder_0285.sh}

# Path to the standalone comparison source. Typical use:
#   VKKH_CU=/path/to/mpcd_vkkh_play.cu bash scripts/run_gpu_objective_profile_0317b.sh
VKKH_CU=${VKKH_CU:-mpcd_vkkh_play.cu}
VKKH_BIN=${VKKH_BIN:-build/mpcd_vkkh_play_0317b}
VKKH_BUILD=${VKKH_BUILD:-1}

NSYS=${NSYS:-nsys}
NSYS_TRACE=${NSYS_TRACE:-cuda,osrt}
NSYS_EXTRA_ARGS=${NSYS_EXTRA_ARGS:-}
NSYS_CPUCTXSW=${NSYS_CPUCTXSW:-process-tree}  # valid values usually: process-tree|system-wide|none
NSYS_CUDA_MEMORY_USAGE=${NSYS_CUDA_MEMORY_USAGE:-true}
NSYS_FALLBACK_ON_ERROR=${NSYS_FALLBACK_ON_ERROR:-1}
USE_NSYS=${USE_NSYS:-auto}   # auto|1|0
TIME_BIN=${TIME_BIN:-/usr/bin/time}

if [[ "$CLEAN_ART_DIR" == "1" || "$CLEAN_ART_DIR" == "true" || "$CLEAN_ART_DIR" == "TRUE" ]]; then
  rm -rf "$ART_DIR"
fi
mkdir -p "$ART_DIR" "$ART_DIR/logs" "$ART_DIR/nsys" "$ART_DIR/time" "$ART_DIR/runs"

if [[ "$SRC_BUILD" == "1" && "$RUN_SRC" == "1" ]]; then
  echo "[0317b-profile] building SRC binary: $SRC_BIN"
  OUT="$SRC_BIN" CUDA_ARCH_FLAGS="${CUDA_ARCH_FLAGS:-}" bash "$SRC_BUILD_SCRIPT"
fi
if [[ "$RUN_SRC" == "1" && ! -x "$SRC_BIN" ]]; then
  echo "[0317b-profile] ERROR: SRC_BIN missing/not executable: $SRC_BIN" >&2
  exit 127
fi

if [[ "$RUN_VKKH" == "1" ]]; then
  if [[ ! -f "$VKKH_CU" ]]; then
    echo "[0317b-profile] WARNING: VKKH_CU not found: $VKKH_CU" >&2
    echo "[0317b-profile]          Set VKKH_CU=/path/to/mpcd_vkkh_play.cu, or set RUN_VKKH=0." >&2
    RUN_VKKH=0
  elif [[ "$VKKH_BUILD" == "1" ]]; then
    echo "[0317b-profile] building VKKH binary: $VKKH_BIN from $VKKH_CU"
    mkdir -p "$(dirname "$VKKH_BIN")"
    nvcc ${VKKH_NVCCFLAGS:--O3 -std=c++17} ${CUDA_ARCH_FLAGS:-} -Xcompiler -fopenmp "$VKKH_CU" -o "$VKKH_BIN"
  fi
fi
if [[ "$RUN_VKKH" == "1" && ! -x "$VKKH_BIN" ]]; then
  echo "[0317b-profile] ERROR: VKKH_BIN missing/not executable: $VKKH_BIN" >&2
  exit 127
fi

have_nsys=0
if command -v "$NSYS" >/dev/null 2>&1; then have_nsys=1; fi
if [[ "$USE_NSYS" == "1" && "$have_nsys" != "1" ]]; then
  echo "[0317b-profile] ERROR: requested USE_NSYS=1 but nsys not found ($NSYS)." >&2
  exit 127
fi
if [[ "$USE_NSYS" == "0" ]]; then have_nsys=0; fi
if [[ "$have_nsys" == "1" ]]; then
  echo "[0317b-profile] Nsight Systems available: $($NSYS --version 2>/dev/null | head -1 || echo nsys)"
else
  echo "[0317b-profile] Nsight Systems unavailable/disabled; using /usr/bin/time fallback."
fi

MANIFEST="$ART_DIR/gpu_objective_profile_0317b_manifest.csv"
printf 'target,repeat,profiler,profilerRequested,steps,nx,ny,gamma,binary,runRoot,reportPrefix,timeFile,stdoutFile,stderrFile,exitCode,note\n' > "$MANIFEST"
append_manifest() {
  python3 - "$MANIFEST" "$@" <<'PY'
import csv, sys
with open(sys.argv[1], 'a', newline='') as f:
    csv.writer(f).writerow(sys.argv[2:])
PY
}

RUN_TIMED_EFFECTIVE_PROFILER=""
RUN_TIMED_NOTE=""

run_time_only() {
  local time_file=$1 stdout_file=$2 stderr_file=$3
  shift 3
  "$TIME_BIN" -f 'elapsed_seconds,%e\nuser_seconds,%U\nsys_seconds,%S\nmax_rss_kb,%M\nexit_code,%x' -o "$time_file" \
    "$@" >"$stdout_file" 2>"$stderr_file"
}

run_nsys_full() {
  local prefix=$1 time_file=$2 stdout_file=$3 stderr_file=$4
  shift 4
  local args=(profile --force-overwrite=true --trace="$NSYS_TRACE" --sample=none)
  if [[ -n "$NSYS_CPUCTXSW" ]]; then
    args+=(--cpuctxsw="$NSYS_CPUCTXSW")
  fi
  if [[ -n "$NSYS_CUDA_MEMORY_USAGE" ]]; then
    args+=(--cuda-memory-usage="$NSYS_CUDA_MEMORY_USAGE")
  fi
  # shellcheck disable=SC2206
  local extra=( $NSYS_EXTRA_ARGS )
  "$NSYS" "${args[@]}" -o "$prefix" "${extra[@]}" \
    "$TIME_BIN" -f 'elapsed_seconds,%e\nuser_seconds,%U\nsys_seconds,%S\nmax_rss_kb,%M\nexit_code,%x' -o "$time_file" \
    "$@" >"$stdout_file" 2>"$stderr_file"
}

run_nsys_minimal() {
  local prefix=$1 time_file=$2 stdout_file=$3 stderr_file=$4
  shift 4
  "$NSYS" profile --force-overwrite=true --trace="$NSYS_TRACE" --sample=none -o "$prefix" \
    "$TIME_BIN" -f 'elapsed_seconds,%e\nuser_seconds,%U\nsys_seconds,%S\nmax_rss_kb,%M\nexit_code,%x' -o "$time_file" \
    "$@" >"$stdout_file" 2>"$stderr_file"
}

run_timed() {
  local profiler=$1 prefix=$2 time_file=$3 stdout_file=$4 stderr_file=$5
  shift 5
  mkdir -p "$(dirname "$time_file")" "$(dirname "$stdout_file")" "$(dirname "$stderr_file")"
  RUN_TIMED_EFFECTIVE_PROFILER="$profiler"
  RUN_TIMED_NOTE=""
  set +e
  local rc=0
  if [[ "$profiler" == "nsys" ]]; then
    run_nsys_full "$prefix" "$time_file" "$stdout_file" "$stderr_file" "$@"
    rc=$?
    if [[ "$rc" != "0" && "$NSYS_FALLBACK_ON_ERROR" == "1" ]]; then
      mv -f "$stderr_file" "${stderr_file}.nsys_full_failed.log" 2>/dev/null || true
      mv -f "$stdout_file" "${stdout_file}.nsys_full_failed.log" 2>/dev/null || true
      rm -f "${prefix}.nsys-rep" "${prefix}.qdrep" "${prefix}.sqlite" 2>/dev/null || true
      echo "[0317b-profile] nsys full failed for prefix=$prefix; retrying minimal nsys." >&2
      run_nsys_minimal "$prefix" "$time_file" "$stdout_file" "$stderr_file" "$@"
      rc=$?
      if [[ "$rc" == "0" ]]; then
        RUN_TIMED_EFFECTIVE_PROFILER="nsys_minimal"
        RUN_TIMED_NOTE="nsys_full_failed_then_minimal_succeeded"
      fi
    fi
    if [[ "$rc" != "0" && "$NSYS_FALLBACK_ON_ERROR" == "1" ]]; then
      mv -f "$stderr_file" "${stderr_file}.nsys_minimal_failed.log" 2>/dev/null || true
      mv -f "$stdout_file" "${stdout_file}.nsys_minimal_failed.log" 2>/dev/null || true
      rm -f "${prefix}.nsys-rep" "${prefix}.qdrep" "${prefix}.sqlite" 2>/dev/null || true
      echo "[0317b-profile] nsys minimal failed for prefix=$prefix; falling back to /usr/bin/time." >&2
      run_time_only "$time_file" "$stdout_file" "$stderr_file" "$@"
      rc=$?
      RUN_TIMED_EFFECTIVE_PROFILER="time_after_nsys_fail"
      RUN_TIMED_NOTE="nsys_failed_then_time_fallback"
    fi
  else
    run_time_only "$time_file" "$stdout_file" "$stderr_file" "$@"
    rc=$?
  fi
  return "$rc"
}

# Avoid recursive shell quoting problems by executing target commands through helper files.
make_helper() {
  local helper=$1 target=$2 run_root=$3
  cat > "$helper" <<EOF_HELPER
#!/usr/bin/env bash
set -euo pipefail
cd "$ROOT"
if [[ "$target" == "src_cuda_v2_0315m" ]]; then
  env BIN="$SRC_BIN" AUTO_BUILD=0 LIVE_PROGRESS=0 CLEAN_RUN_ROOT=1 \\
    RUN_ROOT="$run_root" Lx="$Lx" Ly="$Ly" NX="$NX" NY="$NY" GAMMA="$GAMMA" STEPS="$STEPS" DT="$DT" KBT="$KBT" SEED="$SEED" \\
    UIN="$UIN" CYLINDER_CX="$CYLINDER_CX" CYLINDER_CY="$CYLINDER_CY" CYLINDER_R="$CYLINDER_R" \\
    INACTIVE_SLOTS="$INACTIVE_SLOTS" THREADS="$THREADS" \\
    SUMMARY_EVERY=1000000000 DUMP_STATE_EVERY=0 SRC_GPU_DEMO_REQUIRE_DUMPS=0 DUMP_ROLE_FILTER=fluid SUMMARY_ROLE_FILTER=fluid \\
    RESAMPLING_ENABLE=0 RESAMPLING_SURVEY_ENABLE=0 GUARD_EVERY=999999 \\
    bash "$SRC_RUN_SCRIPT"
else
  mkdir -p "$run_root/output"
  "$VKKH_BIN" --mode vk --Lx "$Lx" --Ly "$Ly" --Nx "$NX" --Ny "$NY" --gamma "$GAMMA" \\
    --steps "$STEPS" --dt "$DT" --kBT "$KBT" --U0 "$UIN" --seed "$SEED" \\
    --xc "$CYLINDER_CX" --yc "$CYLINDER_CY" --Rc "$CYLINDER_R" \\
    --thermostat 1 --keepMeanFlow 0 --xInletInject 1 --reinjectBackflow 1 --injectRandomY 1 \\
    --solid 1 --vis 0 --writeCSV 0 --dumpStride 1000000000 --logStride 1000000000 \\
    --outDir "$run_root/output"
fi
EOF_HELPER
  chmod +x "$helper"
}

run_target() {
  local target=$1 rep=$2
  local profiler="time"
  if [[ "$have_nsys" == "1" ]]; then profiler="nsys"; fi
  local run_root="$ART_DIR/runs/${target}/rep_${rep}"
  local prefix="$ART_DIR/nsys/${target}_rep_${rep}"
  local time_file="$ART_DIR/time/${target}_rep_${rep}.time.csv"
  local stdout_file="$ART_DIR/logs/${target}_rep_${rep}.stdout.log"
  local stderr_file="$ART_DIR/logs/${target}_rep_${rep}.stderr.log"
  local helper="$ART_DIR/run_${target}_rep_${rep}.sh"
  mkdir -p "$run_root"
  make_helper "$helper" "$target" "$run_root"
  echo "[0317b-profile] run target=$target rep=$rep profiler=$profiler"
  set +e
  run_timed "$profiler" "$prefix" "$time_file" "$stdout_file" "$stderr_file" "$helper"
  local rc=$?
  set -e
  append_manifest "$target" "$rep" "$RUN_TIMED_EFFECTIVE_PROFILER" "$profiler" "$STEPS" "$NX" "$NY" "$GAMMA" \
    "$([[ "$target" == src_cuda_v2_0315m ]] && echo "$SRC_BIN" || echo "$VKKH_BIN")" \
    "$run_root" "$prefix" "$time_file" "$stdout_file" "$stderr_file" "$rc" "$RUN_TIMED_NOTE"
  if [[ "$rc" != "0" ]]; then
    echo "[0317b-profile] WARNING: target=$target rep=$rep failed rc=$rc" >&2
    tail -80 "$stderr_file" >&2 || true
  fi
}

warmup_target() {
  local target=$1
  local run_root="$ART_DIR/warmup_${target}"
  local helper="$ART_DIR/warmup_${target}.sh"
  local stdout_file="$ART_DIR/logs/warmup_${target}.stdout.log"
  local stderr_file="$ART_DIR/logs/warmup_${target}.stderr.log"
  local time_file="$ART_DIR/time/warmup_${target}.time.csv"
  make_helper "$helper" "$target" "$run_root"
  echo "[0317b-profile] warmup target=$target profiler=time"
  set +e
  run_time_only "$time_file" "$stdout_file" "$stderr_file" "$helper"
  local rc=$?
  set -e
  if [[ "$rc" != "0" ]]; then
    echo "[0317b-profile] WARNING: warmup target=$target failed rc=$rc" >&2
    tail -80 "$stderr_file" >&2 || true
  fi
}

if [[ "$WARMUP" == "1" ]]; then
  echo "[0317b-profile] warmup runs are executed with /usr/bin/time only and excluded from manifest."
  if [[ "$RUN_SRC" == "1" ]]; then warmup_target src_cuda_v2_0315m; fi
  if [[ "$RUN_VKKH" == "1" ]]; then warmup_target mpcd_vkkh_play; fi
fi

for rep in $(seq 1 "$REPEATS"); do
  if [[ "$RUN_SRC" == "1" ]]; then run_target src_cuda_v2_0315m "$rep"; fi
  if [[ "$RUN_VKKH" == "1" ]]; then run_target mpcd_vkkh_play "$rep"; fi
done

if [[ "$have_nsys" == "1" ]]; then
  mkdir -p "$ART_DIR/nsys_stats"
  while IFS=, read -r target rep profiler profiler_requested steps nx ny gamma binary run_root prefix time_file stdout_file stderr_file exit_code note; do
    [[ "$target" == "target" ]] && continue
    [[ "$profiler" != nsys* ]] && continue
    repfile="${prefix}.nsys-rep"
    [[ -f "$repfile" ]] || continue
    outprefix="$ART_DIR/nsys_stats/${target}_rep_${rep}"
    echo "[0317b-profile] exporting nsys stats for $target rep=$rep"
    "$NSYS" stats --force-export=true --format csv --output "$outprefix" \
      --report cuda_api_sum,cuda_gpu_kern_sum,cuda_gpu_mem_time_sum,cuda_gpu_mem_size_sum,osrt_sum "$repfile" \
      >"${outprefix}.stdout.txt" 2>"${outprefix}.stderr.txt" || true
  done < "$MANIFEST"
fi

python3 scripts/summarize_gpu_objective_profile_0317b.py "$MANIFEST" "$ART_DIR"

echo "[0317b-profile] manifest: $MANIFEST"
echo "[0317b-profile] summary : $ART_DIR/gpu_objective_profile_0317b_summary.csv"
echo "[0317b-profile] top kernels: $ART_DIR/gpu_objective_profile_0317b_top_kernels.csv"
echo "[0317b-profile] top API    : $ART_DIR/gpu_objective_profile_0317b_top_cuda_api.csv"
