#!/usr/bin/env bash
set -euo pipefail

# 0264 — segmented inlet/outlet classic SRC CUDA resident validation/performance runner.
# Scope: segmented_u_turn_full only, same-face left inlet/outlet segments, wall-like
# complement, no Q6/Q9, no resampling, no virial, no thermostat.
# Q6 and resampling are disabled only in this validator; the resident host/GPU
# freshness protocol remains compatible with a later CPU continuation.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BIN=${BIN:-build/src_mpcd_base_cuda_0264}
ART_DIR=${ART_DIR:-dev_history/artifacts/gpu_cuda_classic_src_io_0264}
GRID_CASES=${GRID_CASES:-"64:64:300 128:128:300"}
CASES=${CASES:-"segmented_u_turn_full"}
GAMMA=${GAMMA:-20}
THREADS=${THREADS:-8}
SEED_BASE=${SEED_BASE:-162064}
STOP_ON_FAIL=${STOP_ON_FAIL:-1}
FORCE_REBUILD=${FORCE_REBUILD:-1}
SUMMARY_EVERY_MODE=${SUMMARY_EVERY_MODE:-final}

BASELINE_MODE_NAME=${BASELINE_MODE_NAME:-cpu_classic_io_segmented_no_thermostat}
RESIDENT_MODE_NAME=${RESIDENT_MODE_NAME:-0264_io_segmented_resident_classic_cuda_no_thermostat}

mkdir -p "$ART_DIR"

if [[ "$FORCE_REBUILD" != "0" && "$FORCE_REBUILD" != "false" && "$FORCE_REBUILD" != "FALSE" ]]; then
  echo "[0264-classic-src-io-segmented-resident] rebuilding $BIN (FORCE_REBUILD=$FORCE_REBUILD)"
  OUT="$BIN" CUDA_ARCH_FLAGS=${CUDA_ARCH_FLAGS:-} bash scripts/build_src_mpcd_cuda_0264.sh
elif [[ ! -x "$BIN" ]]; then
  OUT="$BIN" CUDA_ARCH_FLAGS=${CUDA_ARCH_FLAGS:-} bash scripts/build_src_mpcd_cuda_0264.sh
fi
if [[ ! -x "$BIN" ]]; then
  echo "[0264-classic-src-io-segmented-resident] ERROR: missing binary $BIN" >&2
  exit 127
fi

OUT_CSV=${OUT_CSV:-$ART_DIR/cuda_classic_src_io_segmented_resident_0264.csv}
printf 'caseName,grid,NX,NY,steps,mode,classicSrcCudaMode,residentIo0264,summaryEvery,thermostatEnable,runExitCode,baselineTotalWallTime,modeTotalWallTime,totalWallDelta_s,totalWallSpeedup,baselineMaxCaseWallTime,modeMaxCaseWallTime,maxCaseWallDelta_s,maxCaseWallSpeedup,collisionActiveCalls,collisionTotalSeconds,collisionUploadSeconds,collisionKernelSeconds,collisionDownloadSeconds,collisionSharedParticleStateFraction,collisionSharedCellWorkspaceFraction,failed_metrics,compared_metrics,verdict,stdoutLog,stderrLog,compareCsv,compareSummary\n' > "$OUT_CSV"

summary_times() {
  local summary=$1
  python3 - "$summary" <<'PY'
import csv, math, sys
p=sys.argv[1]
try:
    with open(p, newline='') as f:
        rows=list(csv.DictReader(f))
    vals=[]
    for r in rows:
        v=None
        for k in ('elapsed_s','wallTime','wallTime_s','elapsedSeconds'):
            if k in r and r[k] not in ('', 'nan'):
                v=float(r[k]); break
        if v is not None:
            vals.append(v)
    print(f"{sum(vals) if vals else float('nan')},{max(vals) if vals else float('nan')}")
except Exception:
    print('nan,nan')
PY
}

read_compare_summary() {
  local f=$1
  python3 - "$f" <<'PY'
import csv, sys
failed=999999; compared=0; verdict='FAIL'
try:
    with open(sys.argv[1], newline='') as fh:
        rows=list(csv.DictReader(fh))
    if rows:
        failed=sum(int(float(r.get('failed_metrics', 999999) or 0)) for r in rows)
        compared=sum(int(float(r.get('compared_metrics', 0) or 0)) for r in rows)
        verdict='PASS' if failed == 0 and compared > 0 else 'FAIL'
except Exception:
    pass
print(f'{failed},{compared},{verdict}')
PY
}

collision_stats() {
  local root=$1
  python3 - "$root" <<'PY'
import csv, glob, math, os, sys
rows=[]
for p in glob.glob(os.path.join(sys.argv[1], '*', 'cuda_persistent_src_collision_thermostat_0215.csv')):
    try:
        with open(p, newline='') as f: rows.extend(list(csv.DictReader(f)))
    except FileNotFoundError: pass
if not rows:
    print('0,0,0,0,0,nan,nan')
    raise SystemExit(0)
def vals(k):
    out=[]
    for r in rows:
        try: out.append(float(r.get(k,'nan')))
        except Exception: out.append(float('nan'))
    return [x for x in out if math.isfinite(x)]
def s(k): return sum(vals(k))
def a(k):
    xs=vals(k); return sum(xs)/len(xs) if xs else float('nan')
print(','.join(str(x) for x in [len(rows), s('totalSeconds'), s('uploadSeconds'), s('kernelSeconds'), s('downloadSeconds'), a('sharedParticleStateEnabled'), a('sharedCellWorkspaceEnabled')]))
PY
}

summary_every_for_steps() {
  local steps=$1
  if [[ "${SUMMARY_EVERY_MODE:-final}" == "final" ]]; then
    echo "$steps"
  else
    echo "${SUMMARY_EVERY:-50}"
  fi
}

run_validation_logged() {
  local case_name=$1 nx=$2 ny=$3 steps=$4 root=$5 tag=$6 mode=$7 stdout_log=$8 stderr_log=$9
  local summary_every
  summary_every=$(summary_every_for_steps "$steps")
  local seed=$((SEED_BASE + nx + ny + steps))
  local inactive_slots=${VALIDATION_INACTIVE_SLOTS:-$((GAMMA * ny * 8))}

  local resident=0 persistent_collision=0 collision_shared=0 minimal_download=0 immersed_download=1
  case "$mode" in
    "$BASELINE_MODE_NAME") ;;
    "$RESIDENT_MODE_NAME")
      resident=1; persistent_collision=1; collision_shared=1; minimal_download=1; immersed_download=1 ;;
    *) echo "[0264-classic-src-io-segmented-resident] ERROR: unknown mode $mode" >&2; return 2 ;;
  esac

  rm -rf "$root"
  set +e
  env BIN="$BIN" BUILD_IF_MISSING=0 CASE_LIST="$case_name" \
      NX="$nx" NY="$ny" GAMMA="$GAMMA" STEPS="$steps" SUMMARY_EVERY="$summary_every" \
      THREADS="$THREADS" SEED="$seed" DUMP_STATE_EVERY=0 \
      RUN_ROOT="$root" RUN_TAG="$tag" PROJECTION_BACKEND=cpu PROJECTION_ENABLE=false \
      VALIDATION_INACTIVE_SLOTS="$inactive_slots" \
      SRC_CLASSIC_CUDA_MODE_ENABLE=true RESAMPLING_ENABLE=false THERMOSTAT_ENABLE=false \
      WALL_THERMAL_NOISE=0 INLET_THERMAL_NOISE=0 \
      MPCD_CUDA_CLASSIC_SRC_PERIODIC_RESIDENT_0260=0 \
      MPCD_CUDA_CLASSIC_SRC_WALL_RESIDENT_0261=0 \
      MPCD_CUDA_CLASSIC_SRC_SOLID_RESIDENT_0262=0 \
      MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263=0 \
      MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263_STRICT=0 \
      MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264="$resident" \
      MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264_STRICT=1 \
      MPCD_CUDA_STREAMING_PERIODIC_0245=0 \
      MPCD_CUDA_STREAMING_WALL_SIMPLE_0246=0 \
      MPCD_CUDA_STREAMING_PISTON_0247B=0 \
      MPCD_CUDA_IMMERSED_RECTANGLE_0247=0 \
      MPCD_CUDA_IMMERSED_RECTANGLE_0247_DOWNLOAD_ALL=1 \
      MPCD_CUDA_IMMERSED_RECTANGLE_0247_THREADS="${MPCD_CUDA_IMMERSED_RECTANGLE_0247_THREADS:-256}" \
      MPCD_CUDA_INLET_OUTLET_FULLFACE_0249A=0 \
      MPCD_CUDA_INLET_OUTLET_SEGMENTED_0249B=0 \
      MPCD_CUDA_CELL_MOMENTS_USE=0 \
      MPCD_CUDA_THERMOSTAT_USE=0 \
      MPCD_CUDA_THERMOSTAT_PERSISTENT_0258=0 \
      MPCD_CUDA_SRC_COLLISION_USE=0 \
      MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE="$persistent_collision" \
      MPCD_CUDA_PERSISTENT_SRC_COLLISION_STRICT=1 \
      MPCD_CUDA_PERSISTENT_SRC_COLLISION_ACTIVE_STRICT=1 \
      MPCD_CUDA_PERSISTENT_SRC_COLLISION_MINIMAL_DOWNLOAD_0257="$minimal_download" \
      MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251="$collision_shared" \
      MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251_STRICT=1 \
      MPCD_CUDA_PERSISTENT_SRC_COLLISION_WALL_SIMPLE_0253="$persistent_collision" \
      MPCD_CUDA_PERSISTENT_SRC_COLLISION_IMMERSED_RECT_0254=0 \
      MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE=0 \
      MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260=0 \
      MPCD_CUDA_PERSISTENT_PARTICLE_STATE_USE=0 \
      MPCD_CUDA_PERSISTENT_PARTICLE_METADATA_CACHE=0 \
      MPCD_CUDA_PERSISTENT_CELL_WORKSPACE_USE=0 \
      MPCD_CUDA_PERSISTENT_THREADS_PER_BLOCK="${MPCD_CUDA_PERSISTENT_THREADS_PER_BLOCK:-256}" \
      MPCD_CUDA_RESAMPLING_PERSISTENT_0240=0 \
      bash scripts/run_validation_mono_config_0162.sh >"$stdout_log" 2>"$stderr_log"
  local rc=$?
  set -e
  return $rc
}

compare_runs() {
  local base_root=$1 run_root=$2 compare_csv=$3 compare_summary=$4 stdout_log=$5 stderr_log=$6
  if [[ -f "$base_root/validation_summary_0162.csv" && -f "$run_root/validation_summary_0162.csv" ]]; then
    set +e
    python3 scripts/compare_validation_mono_config_0162.py \
      --origin "$base_root" --optimized "$run_root" \
      --out "$compare_csv" --summary-out "$compare_summary" >>"$stdout_log" 2>>"$stderr_log"
    local rc=$?
    set -e
    return $rc
  fi
  return 3
}

for grid_spec in $GRID_CASES; do
  IFS=: read -r nx ny steps <<<"$grid_spec"
  if [[ -z "${steps:-}" ]]; then
    echo "[0264-classic-src-io-segmented-resident] ERROR: GRID_CASES entries must be NX:NY:STEPS, got $grid_spec" >&2
    exit 2
  fi
  grid_tag="${nx}x${ny}_s${steps}"
  for case_name in $CASES; do
    if [[ "$case_name" != "segmented_u_turn_full" ]]; then
      echo "[0264-classic-src-io-segmented-resident] ERROR: 0264 is limited to segmented_u_turn_full, got $case_name" >&2
      exit 2
    fi
    summary_every_current=$(summary_every_for_steps "$steps")
    base_root="$ART_DIR/${case_name}_${BASELINE_MODE_NAME}_${grid_tag}"
    base_stdout="$ART_DIR/${case_name}_${BASELINE_MODE_NAME}_${grid_tag}.stdout.log"
    base_stderr="$ART_DIR/${case_name}_${BASELINE_MODE_NAME}_${grid_tag}.stderr.log"
    echo "[0264-classic-src-io-segmented-resident] running baseline case=$case_name grid=$grid_tag"
    base_rc=0
    run_validation_logged "$case_name" "$nx" "$ny" "$steps" "$base_root" "cuda_classic_src_0264_${case_name}_baseline_${grid_tag}" "$BASELINE_MODE_NAME" "$base_stdout" "$base_stderr" || base_rc=$?
    if [[ "$base_rc" != "0" ]]; then
      echo "[0264-classic-src-io-segmented-resident] baseline returned rc=$base_rc; continuing to write diagnostic CSV row" >&2
    fi
    IFS=, read -r base_total base_max <<<"$(summary_times "$base_root/validation_summary_0162.csv")"

    mode="$RESIDENT_MODE_NAME"
    run_root="$ART_DIR/${case_name}_${mode}_${grid_tag}"
    stdout_log="$ART_DIR/${case_name}_${mode}_${grid_tag}.stdout.log"
    stderr_log="$ART_DIR/${case_name}_${mode}_${grid_tag}.stderr.log"
    compare_csv="$ART_DIR/${case_name}_${mode}_${grid_tag}_compare.csv"
    compare_summary="$ART_DIR/${case_name}_${mode}_${grid_tag}_compare_summary.csv"
    echo "[0264-classic-src-io-segmented-resident] running case=$case_name mode=$mode grid=$grid_tag"
    rc=0
    run_validation_logged "$case_name" "$nx" "$ny" "$steps" "$run_root" "cuda_classic_src_0264_${case_name}_${mode}_${grid_tag}" "$mode" "$stdout_log" "$stderr_log" || rc=$?
    if [[ "$rc" != "0" ]]; then
      echo "[0264-classic-src-io-segmented-resident] resident mode returned rc=$rc; continuing to write diagnostic CSV row" >&2
    fi
    cmp_rc=0
    compare_runs "$base_root" "$run_root" "$compare_csv" "$compare_summary" "$stdout_log" "$stderr_log" || cmp_rc=$?
    IFS=, read -r failed compared verdict <<<"$(read_compare_summary "$compare_summary")"
    IFS=, read -r mode_total mode_max <<<"$(summary_times "$run_root/validation_summary_0162.csv")"
    IFS=, read -r coll_calls coll_total coll_upload coll_kernel coll_download coll_shared_p coll_shared_c <<<"$(collision_stats "$run_root")"
    speedup=$(python3 - <<PY
b=float('$base_total'); m=float('$mode_total')
print(b/m if m>0 else float('nan'))
PY
)
    max_speedup=$(python3 - <<PY
b=float('$base_max'); m=float('$mode_max')
print(b/m if m>0 else float('nan'))
PY
)
    delta=$(python3 - <<PY
b=float('$base_total'); m=float('$mode_total')
print(m-b)
PY
)
    max_delta=$(python3 - <<PY
b=float('$base_max'); m=float('$mode_max')
print(m-b)
PY
)
    printf '%s,%s,%s,%s,%s,%s,1,1,%s,0,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
      "$case_name" "$grid_tag" "$nx" "$ny" "$steps" "$mode" "$summary_every_current" "$rc" \
      "$base_total" "$mode_total" "$delta" "$speedup" "$base_max" "$mode_max" "$max_delta" "$max_speedup" \
      "$coll_calls" "$coll_total" "$coll_upload" "$coll_kernel" "$coll_download" "$coll_shared_p" "$coll_shared_c" \
      "$failed" "$compared" "$verdict" "$stdout_log" "$stderr_log" "$compare_csv" "$compare_summary" >> "$OUT_CSV"
    echo "[0264-classic-src-io-segmented-resident] $verdict case=$case_name grid=$grid_tag mode=$mode baselineRc=$base_rc runRc=$rc failed=$failed/$compared wall=$mode_total baseline=$base_total"
    if [[ "$STOP_ON_FAIL" == "1" && ( "$base_rc" != "0" || "$rc" != "0" || "$verdict" != "PASS" ) ]]; then
      echo "[0264-classic-src-io-segmented-resident] stopping after failure; see baseline stderr: $base_stderr ; resident stderr: $stderr_log" >&2
      exit 1
    fi
  done
done

echo "[0264-classic-src-io-segmented-resident] wrote $OUT_CSV"
