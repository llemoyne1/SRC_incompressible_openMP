#!/usr/bin/env bash
set -euo pipefail

# 0280b — segmented inlet/outlet validation for CUDA persistent SRC+thermostat (runner fix).
#
# Scope: segmented_u_turn_full, classic SRC only, Q6/resampling/virial disabled.
# Goal: compare CPU segmented boundary + CPU collision + CPU thermostat against
# the resident CUDA segmented inlet/outlet boundary path + shared-state
# fused persistent CUDA SRC+thermostat consumer.
#
# This validator intentionally keeps Q6/resampling/virial disabled only for this
# discriminant classic-only subset. The architecture still preserves later paths:
# CUDA SRC -> CPU Q6/resampling/virial -> CUDA post-CPU thermostat, as validated
# separately for piston in 0278.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BIN=${BIN:-build/src_mpcd_base_cuda_0280b}
ART_DIR=${ART_DIR:-dev_history/artifacts/gpu_cuda_persistent_src_thermostat_io_segmented_0280b}
GRID_CASES=${GRID_CASES:-"64:64:120"}
CASES=${CASES:-"segmented_u_turn_full"}
GAMMA=${GAMMA:-20}
THREADS=${THREADS:-8}
SEED_BASE=${SEED_BASE:-162801}
STOP_ON_FAIL=${STOP_ON_FAIL:-1}
FORCE_REBUILD=${FORCE_REBUILD:-1}
SUMMARY_EVERY_MODE=${SUMMARY_EVERY_MODE:-final}
VALIDATION_INACTIVE_SLOTS=${VALIDATION_INACTIVE_SLOTS:-}

BASELINE_MODE_NAME=${BASELINE_MODE_NAME:-cpu_io_segmented_src_thermostat}
CUDA_MODE_NAME=${CUDA_MODE_NAME:-0280b_cuda_io_segmented_src_fused_thermostat}

mkdir -p "$ART_DIR"

if [[ "$FORCE_REBUILD" != "0" && "$FORCE_REBUILD" != "false" && "$FORCE_REBUILD" != "FALSE" ]]; then
  echo "[0280b-cuda-thermostat-io-segmented] rebuilding $BIN (FORCE_REBUILD=$FORCE_REBUILD)"
  OUT="$BIN" CUDA_ARCH_FLAGS=${CUDA_ARCH_FLAGS:-} bash scripts/build_src_mpcd_cuda_0280b.sh
elif [[ ! -x "$BIN" ]]; then
  OUT="$BIN" CUDA_ARCH_FLAGS=${CUDA_ARCH_FLAGS:-} bash scripts/build_src_mpcd_cuda_0280b.sh
fi
if [[ ! -x "$BIN" ]]; then
  echo "[0280b-cuda-thermostat-io-segmented] ERROR: missing binary $BIN" >&2
  exit 127
fi

OUT_CSV=${OUT_CSV:-$ART_DIR/cuda_persistent_src_thermostat_io_segmented_0280b.csv}
python3 - "$OUT_CSV" <<'PY'
import csv, sys
header = [
    'caseName','grid','NX','NY','steps','mode','classicSrcCudaMode','thermostatEnable',
    'projectionEnable','resamplingEnable','closedCapacityResponseEnable','wallThermalNoise',
    'inletThermalNoise','ioSegmentedResidentFlag','fusedSrcThermostatUse',
    'sharedThermostat0251_0260','postCpuThermostatPersistent0258',
    'runExitCode','compareExitCode',
    'baselineTotalWallTime','modeTotalWallTime','totalWallDelta_s','totalWallSpeedup',
    'collisionActiveCalls','collisionTotalSeconds','collisionUploadSeconds','collisionKernelSeconds',
    'collisionDownloadSeconds','collisionSharedParticleStateFraction','collisionSharedCellWorkspaceFraction',
    'thermostatGpuAppliedFraction','thermostatCellsRescaled','thermostatParticlesRescaled',
    'thermostatKBTBeforeMean','thermostatKBTAfterMean',
    'failed_metrics','compared_metrics','verdict','stdoutLog','stderrLog','compareCsv','compareSummary'
]
with open(sys.argv[1], 'w', newline='') as fh:
    csv.writer(fh).writerow(header)
PY

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
    print(f"{sum(vals) if vals else float('nan')}")
except Exception:
    print('nan')
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
        failed=sum(int(float(r.get('failed_metrics', r.get('failed', r.get('nFailed', 999999))) or 0)) for r in rows)
        compared=sum(int(float(r.get('compared_metrics', r.get('compared', r.get('nCompared', 0))) or 0)) for r in rows)
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
        with open(p, newline='') as f:
            rows.extend(list(csv.DictReader(f)))
    except FileNotFoundError:
        pass
if not rows:
    print('0,0,0,0,0,nan,nan,nan,0,0,nan,nan')
    raise SystemExit(0)
def vals(k):
    out=[]
    for r in rows:
        try:
            v=float(r.get(k,'nan'))
            if math.isfinite(v): out.append(v)
        except Exception:
            pass
    return out
def s(k): return sum(vals(k))
def a(k):
    xs=vals(k)
    return sum(xs)/len(xs) if xs else float('nan')
print(','.join(str(x) for x in [
    len(rows), s('totalSeconds'), s('uploadSeconds'), s('kernelSeconds'), s('downloadSeconds'),
    a('sharedParticleStateEnabled'), a('sharedCellWorkspaceEnabled'), a('thermostatAppliedOnGpu'),
    s('thermostatCellsRescaled'), s('thermostatParticlesRescaled'),
    a('thermostatKBTBefore'), a('thermostatKBTAfter')
]))
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

append_csv_row() {
  python3 - "$OUT_CSV" "$@" <<'PY'
import csv, sys
out=sys.argv[1]
row=sys.argv[2:]
with open(out, 'a', newline='') as fh:
    csv.writer(fh).writerow(row)
PY
}

run_validation_logged() {
  local case_name=$1 nx=$2 ny=$3 steps=$4 root=$5 tag=$6 mode=$7 stdout_log=$8 stderr_log=$9
  local summary_every
  summary_every=$(summary_every_for_steps "$steps")
  local seed=$((SEED_BASE + nx + ny + steps))
  local inactive_slots
  if [[ -n "${VALIDATION_INACTIVE_SLOTS:-}" ]]; then
    inactive_slots="$VALIDATION_INACTIVE_SLOTS"
  else
    inactive_slots=$((GAMMA * ny * 8))
  fi

  local io_segmented=0 persistent_collision=0 persistent_thermo=0
  local collision_shared=0 minimal_download=0 shared_thermo_state=0
  case "$mode" in
    "$BASELINE_MODE_NAME") ;;
    "$CUDA_MODE_NAME")
      io_segmented=1
      # Important 0280b fix: the segmented resident boundary already leaves the
      # shared 0251 particle state fresh.  The fused thermostat path itself
      # performs deposit+SRC+thermostat from that shared state, as in the
      # validated periodic resident 0260 runner.  Requesting the collision-only
      # shared consumer at the same time is unnecessary and made the 0280 smoke
      # brittle/opaque when the fused consumer failed to produce a summary row.
      persistent_collision=0
      persistent_thermo=1
      collision_shared=0
      minimal_download=0
      shared_thermo_state=1
      ;;
    *) echo "[0280b-cuda-thermostat-io-segmented] ERROR: unknown mode $mode" >&2; return 2 ;;
  esac

  rm -rf "$root"
  set +e
  env BIN="$BIN" BUILD_IF_MISSING=0 CASE_LIST="$case_name" \
      NX="$nx" NY="$ny" GAMMA="$GAMMA" STEPS="$steps" SUMMARY_EVERY="$summary_every" \
      THREADS="$THREADS" SEED="$seed" DUMP_STATE_EVERY=0 \
      RUN_ROOT="$root" RUN_TAG="$tag" PROJECTION_BACKEND=cpu PROJECTION_ENABLE=false \
      VALIDATION_INACTIVE_SLOTS="$inactive_slots" \
      SRC_CLASSIC_CUDA_MODE_ENABLE=true RESAMPLING_ENABLE=false THERMOSTAT_ENABLE=true \
      WALL_THERMAL_NOISE=0 INLET_THERMAL_NOISE=0 \
      MPCD_CUDA_CLASSIC_SRC_PERIODIC_RESIDENT_0260=0 \
      MPCD_CUDA_CLASSIC_SRC_WALL_RESIDENT_0261=0 \
      MPCD_CUDA_CLASSIC_SRC_SOLID_RESIDENT_0262=0 \
      MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263=0 \
      MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263_STRICT=0 \
      MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264="$io_segmented" \
      MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264_STRICT=1 \
      MPCD_CUDA_STREAMING_PERIODIC_0245=0 \
      MPCD_CUDA_STREAMING_PERIODIC_0245_DOWNLOAD_ALL=1 \
      MPCD_CUDA_STREAMING_WALL_SIMPLE_0246=0 \
      MPCD_CUDA_STREAMING_WALL_SIMPLE_0246_DOWNLOAD_ALL=1 \
      MPCD_CUDA_IMMERSED_RECTANGLE_0247=0 \
      MPCD_CUDA_IMMERSED_RECTANGLE_0247_DOWNLOAD_ALL=1 \
      MPCD_CUDA_IMMERSED_RECTANGLE_0247_THREADS="${MPCD_CUDA_IMMERSED_RECTANGLE_0247_THREADS:-256}" \
      MPCD_CUDA_STREAMING_PISTON_0247B=0 \
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
      MPCD_CUDA_PERSISTENT_SRC_COLLISION_WALL_SIMPLE_0253=0 \
      MPCD_CUDA_PERSISTENT_SRC_COLLISION_IMMERSED_RECT_0254=0 \
      MPCD_CUDA_PERSISTENT_SRC_COLLISION_PISTON_0255=0 \
      MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE="$persistent_thermo" \
      MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_STRICT=1 \
      MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_CONSUME_STRICT=1 \
      MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260="$shared_thermo_state" \
      MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260_STRICT=1 \
      MPCD_CUDA_PERSISTENT_PARTICLE_STATE_USE=0 \
      MPCD_CUDA_PERSISTENT_PARTICLE_METADATA_CACHE=0 \
      MPCD_CUDA_PERSISTENT_CELL_WORKSPACE_USE=0 \
      MPCD_CUDA_PERSISTENT_THREADS_PER_BLOCK=${MPCD_CUDA_PERSISTENT_THREADS_PER_BLOCK:-256} \
      MPCD_CUDA_RESAMPLING_EXTRACTION_USE=0 \
      MPCD_CUDA_RESAMPLING_INSERTION_USE=0 \
      MPCD_CUDA_RESAMPLING_PERSISTENT_0240=0 \
      bash scripts/run_validation_mono_config_0162.sh >"$stdout_log" 2>"$stderr_log"
  local rc=$?
  set -e
  return $rc
}


dump_failure_context() {
  local root=$1 stdout_log=$2 stderr_log=$3
  {
    echo "--- 0280b failure context ---"
    echo "root=$root"
    if [[ -f "$root/validation_summary_0162.csv" ]]; then
      echo "validation_summary_0162.csv lines=$(wc -l < "$root/validation_summary_0162.csv")"
      tail -n 5 "$root/validation_summary_0162.csv" || true
    else
      echo "missing validation_summary_0162.csv"
    fi
    if [[ -f "$root/segmented_u_turn_full/summary_runtime.csv" ]]; then
      echo "summary_runtime.csv lines=$(wc -l < "$root/segmented_u_turn_full/summary_runtime.csv")"
      tail -n 5 "$root/segmented_u_turn_full/summary_runtime.csv" || true
    else
      echo "missing segmented_u_turn_full/summary_runtime.csv"
    fi
    if [[ -f "$root/segmented_u_turn_full.log" ]]; then
      echo "--- tail segmented_u_turn_full.log ---"
      tail -n 80 "$root/segmented_u_turn_full.log" || true
    fi
    if [[ -f "$root/segmented_u_turn_full.time" ]]; then
      echo "--- segmented_u_turn_full.time ---"
      cat "$root/segmented_u_turn_full.time" || true
    fi
    if [[ -f "$stdout_log" ]]; then
      echo "--- tail runner stdout log ---"
      tail -n 80 "$stdout_log" || true
    fi
    if [[ -f "$stderr_log" ]]; then
      echo "--- tail runner stderr log ---"
      tail -n 80 "$stderr_log" || true
    fi
    echo "--- end 0280b failure context ---"
  } >> "$stderr_log" 2>&1 || true
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
  IFS=: read -r nx ny steps extra <<<"$grid_spec"
  if [[ -n "${extra:-}" || -z "${steps:-}" ]]; then
    echo "[0280b-cuda-thermostat-io-segmented] ERROR: GRID_CASES entries must be NX:NY:STEPS, got $grid_spec" >&2
    exit 2
  fi
  grid_tag="${nx}x${ny}_s${steps}"
  for case_name in $CASES; do
    if [[ "$case_name" != "segmented_u_turn_full" ]]; then
      echo "[0280b-cuda-thermostat-io-segmented] ERROR: 0280 is limited to segmented_u_turn_full, got $case_name" >&2
      exit 2
    fi

    base_root="$ART_DIR/${case_name}_${BASELINE_MODE_NAME}_${grid_tag}"
    base_stdout="$ART_DIR/${case_name}_${BASELINE_MODE_NAME}_${grid_tag}.stdout.log"
    base_stderr="$ART_DIR/${case_name}_${BASELINE_MODE_NAME}_${grid_tag}.stderr.log"
    echo "[0280b-cuda-thermostat-io-segmented] running baseline case=$case_name grid=$grid_tag"
    base_rc=0
    run_validation_logged "$case_name" "$nx" "$ny" "$steps" "$base_root" "cuda_thermostat_io_segmented_0280b_${case_name}_baseline_${grid_tag}" "$BASELINE_MODE_NAME" "$base_stdout" "$base_stderr" || base_rc=$?
    base_total=$(summary_times "$base_root/validation_summary_0162.csv")

    run_root="$ART_DIR/${case_name}_${CUDA_MODE_NAME}_${grid_tag}"
    stdout_log="$ART_DIR/${case_name}_${CUDA_MODE_NAME}_${grid_tag}.stdout.log"
    stderr_log="$ART_DIR/${case_name}_${CUDA_MODE_NAME}_${grid_tag}.stderr.log"
    compare_csv="$ART_DIR/${case_name}_${CUDA_MODE_NAME}_${grid_tag}_compare.csv"
    compare_summary="$ART_DIR/${case_name}_${CUDA_MODE_NAME}_${grid_tag}_compare_summary.csv"
    echo "[0280b-cuda-thermostat-io-segmented] running CUDA fused thermostat case=$case_name grid=$grid_tag"
    rc=0
    run_validation_logged "$case_name" "$nx" "$ny" "$steps" "$run_root" "cuda_thermostat_io_segmented_0280b_${case_name}_${CUDA_MODE_NAME}_${grid_tag}" "$CUDA_MODE_NAME" "$stdout_log" "$stderr_log" || rc=$?
    cmp_rc=0
    compare_runs "$base_root" "$run_root" "$compare_csv" "$compare_summary" "$stdout_log" "$stderr_log" || cmp_rc=$?
    IFS=, read -r failed compared verdict <<<"$(read_compare_summary "$compare_summary")"
    if [[ "$base_rc" != "0" || "$rc" != "0" || "$cmp_rc" != "0" ]]; then verdict="FAIL"; fi
    mode_total=$(summary_times "$run_root/validation_summary_0162.csv")
    IFS=, read -r coll_calls coll_total coll_upload coll_kernel coll_download coll_shared_p coll_shared_c coll_thermo_gpu thermo_cells thermo_particles thermo_kbt_before thermo_kbt_after <<<"$(collision_stats "$run_root")"
    speedup=$(python3 - <<PY
import math
b=float('$base_total'); m=float('$mode_total')
print(b/m if math.isfinite(b) and math.isfinite(m) and m>0 else float('nan'))
PY
)
    delta=$(python3 - <<PY
import math
b=float('$base_total'); m=float('$mode_total')
print(m-b if math.isfinite(b) and math.isfinite(m) else float('nan'))
PY
)
    append_csv_row \
      "$case_name" "$grid_tag" "$nx" "$ny" "$steps" "$CUDA_MODE_NAME" 1 1 \
      false false false 0 0 1 1 1 0 "$rc" "$cmp_rc" \
      "$base_total" "$mode_total" "$delta" "$speedup" \
      "$coll_calls" "$coll_total" "$coll_upload" "$coll_kernel" "$coll_download" "$coll_shared_p" "$coll_shared_c" "$coll_thermo_gpu" \
      "$thermo_cells" "$thermo_particles" "$thermo_kbt_before" "$thermo_kbt_after" \
      "$failed" "$compared" "$verdict" "$stdout_log" "$stderr_log" "$compare_csv" "$compare_summary"
    echo "[0280b-cuda-thermostat-io-segmented] $verdict case=$case_name grid=$grid_tag failed=$failed/$compared wall=$mode_total baseline=$base_total thermoGpu=$coll_thermo_gpu sharedThermo=$coll_shared_p"
    if [[ "$STOP_ON_FAIL" == "1" && ( "$base_rc" != "0" || "$rc" != "0" || "$verdict" != "PASS" ) ]]; then
      dump_failure_context "$run_root" "$stdout_log" "$stderr_log"
      echo "[0280b-cuda-thermostat-io-segmented] stopping after failure; see $stderr_log" >&2
      exit 1
    fi
  done
done

echo "[0280b-cuda-thermostat-io-segmented] wrote $OUT_CSV"
echo "[0280b-cuda-thermostat-io-segmented] shared-state fused SRC thermostat is enabled only for this classic-only segmented inlet/outlet validation."
