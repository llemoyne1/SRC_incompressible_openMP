#!/usr/bin/env bash
set -euo pipefail

# 0278 — piston/mobile-wall validation for the CUDA thermostat.
#
# This deliberately does NOT use the fused collision->thermostat path
# (MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE=0). For piston_virial_full the
# physical order can include CPU Q6/projection, resampling and closed-capacity
# virial/capacity kicks after SRC collision and before thermostat. Therefore
# the CUDA thermostat validated here is the post-CPU-stage persistent 0258 path:
#
#   CUDA piston streaming + CUDA persistent SRC collision
#   -> CPU Q6/resampling/capacity/virial stages when enabled
#   -> CUDA persistent cell-relative thermostat 0258
#
# This keeps the future CPU Q6/OpenMP, CUDA/CPU resampling, virial and later Q6
# CUDA paths re-activatable. The validator compares against a CPU baseline.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BIN=${BIN:-build/src_mpcd_base_cuda_0278}
ART_DIR=${ART_DIR:-dev_history/artifacts/gpu_cuda_persistent_src_thermostat_piston_0278}
GRID_CASES=${GRID_CASES:-"64:64:120"}
CASES=${CASES:-"piston_virial_full"}
GAMMA=${GAMMA:-20}
THREADS=${THREADS:-8}
SEED_BASE=${SEED_BASE:-162780}
STOP_ON_FAIL=${STOP_ON_FAIL:-1}
FORCE_REBUILD=${FORCE_REBUILD:-1}
SUMMARY_EVERY_MODE=${SUMMARY_EVERY_MODE:-final}
PROJECTION_BACKEND=${PROJECTION_BACKEND:-cpu}
PROJECTION_ENABLE=${PROJECTION_ENABLE:-true}
RESAMPLING_ENABLE=${RESAMPLING_ENABLE:-true}
USE_CUDA_RESAMPLING=${USE_CUDA_RESAMPLING:-1}
WALL_THERMAL_NOISE=${WALL_THERMAL_NOISE:-0}

BASELINE_MODE_NAME=${BASELINE_MODE_NAME:-cpu_piston_src_thermostat}
CUDA_MODE_NAME=${CUDA_MODE_NAME:-0278_cuda_piston_src_postcpu_thermostat}

mkdir -p "$ART_DIR"

if [[ "$FORCE_REBUILD" != "0" && "$FORCE_REBUILD" != "false" && "$FORCE_REBUILD" != "FALSE" ]]; then
  echo "[0278-cuda-thermostat-piston] rebuilding $BIN (FORCE_REBUILD=$FORCE_REBUILD)"
  OUT="$BIN" CUDA_ARCH_FLAGS=${CUDA_ARCH_FLAGS:-} bash scripts/build_src_mpcd_cuda_0278.sh
elif [[ ! -x "$BIN" ]]; then
  OUT="$BIN" CUDA_ARCH_FLAGS=${CUDA_ARCH_FLAGS:-} bash scripts/build_src_mpcd_cuda_0278.sh
fi
if [[ ! -x "$BIN" ]]; then
  echo "[0278-cuda-thermostat-piston] ERROR: missing binary $BIN" >&2
  exit 127
fi

OUT_CSV=${OUT_CSV:-$ART_DIR/cuda_persistent_src_thermostat_piston_0278.csv}
python3 - "$OUT_CSV" <<'PY'
import csv, sys
header = [
    'caseName','grid','NX','NY','steps','mode','classicSrcCudaMode','projectionEnable',
    'resamplingEnable','cudaResamplingRequested','closedCapacityPistonCase','wallThermalNoise',
    'fusedSrcThermostatUse','postCpuThermostatPersistent0258','runExitCode','compareExitCode',
    'baselineTotalWallTime','modeTotalWallTime','totalWallDelta_s','totalWallSpeedup',
    'collisionActiveCalls','collisionTotalSeconds','collisionUploadSeconds','collisionKernelSeconds',
    'collisionDownloadSeconds','collisionSharedParticleStateFraction','collisionSharedCellWorkspaceFraction',
    'collisionThermostatAppliedOnGpuFraction','thermostatActiveCalls','thermostatTotalSeconds',
    'thermostatUploadSeconds','thermostatKineticKernelSeconds','thermostatScaleKernelSeconds',
    'thermostatApplyKernelSeconds','thermostatDownloadSeconds','thermostatParticlesVisitedPerCall',
    'thermostatCellsRescaledPerCall','thermostatParticlesRescaledPerCall',
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
    print('0,0,0,0,0,nan,nan,nan')
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
    a('sharedParticleStateEnabled'), a('sharedCellWorkspaceEnabled'), a('thermostatAppliedOnGpu')
]))
PY
}

thermostat_stats() {
  local root=$1
  python3 - "$root" <<'PY'
import csv, glob, math, os, sys
rows=[]
for p in glob.glob(os.path.join(sys.argv[1], '*', 'cuda_cell_thermostat_active_0207.csv')):
    try:
        with open(p, newline='') as f:
            rows.extend(list(csv.DictReader(f)))
    except FileNotFoundError:
        pass
if not rows:
    print('0,0,0,0,0,0,0,nan,nan,nan,nan,nan')
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
    len(rows), s('totalSeconds'), s('uploadSeconds'), s('kineticKernelSeconds'),
    s('scaleKernelSeconds'), s('applyKernelSeconds'), s('downloadSeconds'),
    a('particlesVisited'), a('cellsRescaled'), a('particlesRescaled'),
    a('kBTBefore'), a('kBTAfter')
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

  local boundary_cuda=0 persistent_collision=0 collision_shared_0251=0 persistent_thermostat_0258=0
  local cuda_resampling=0 resampling_download_all=1 resampling_host_shadow=0 resampling_upload_mode=all

  case "$mode" in
    "$BASELINE_MODE_NAME") ;;
    "$CUDA_MODE_NAME")
      boundary_cuda=1
      persistent_collision=1
      collision_shared_0251=1
      persistent_thermostat_0258=1
      if [[ "$USE_CUDA_RESAMPLING" != "0" && "$USE_CUDA_RESAMPLING" != "false" && "$USE_CUDA_RESAMPLING" != "FALSE" ]]; then
        cuda_resampling=1
        resampling_download_all=0
        resampling_host_shadow=1
        resampling_upload_mode=roles_only
      fi
      ;;
    *) echo "[0278-cuda-thermostat-piston] ERROR: unknown mode $mode" >&2; return 2 ;;
  esac

  rm -rf "$root"
  set +e
  env BIN="$BIN" BUILD_IF_MISSING=0 CASE_LIST="$case_name" WALL_THERMAL_NOISE="$WALL_THERMAL_NOISE" \
      NX="$nx" NY="$ny" GAMMA="$GAMMA" STEPS="$steps" SUMMARY_EVERY="$summary_every" \
      THREADS="$THREADS" SEED="$seed" DUMP_STATE_EVERY=0 \
      RUN_ROOT="$root" RUN_TAG="$tag" PROJECTION_BACKEND="$PROJECTION_BACKEND" PROJECTION_ENABLE="$PROJECTION_ENABLE" \
      SRC_CLASSIC_CUDA_MODE_ENABLE=true RESAMPLING_ENABLE="$RESAMPLING_ENABLE" THERMOSTAT_ENABLE=true \
      MPCD_CUDA_CLASSIC_SRC_PERIODIC_RESIDENT_0260=0 \
      MPCD_CUDA_CLASSIC_SRC_WALL_RESIDENT_0261=0 \
      MPCD_CUDA_CLASSIC_SRC_SOLID_RESIDENT_0262=0 \
      MPCD_CUDA_CLASSIC_SRC_IO_FULLFACE_RESIDENT_0263=0 \
      MPCD_CUDA_CLASSIC_SRC_IO_SEGMENTED_RESIDENT_0264=0 \
      MPCD_CUDA_STREAMING_PERIODIC_0245="$boundary_cuda" \
      MPCD_CUDA_STREAMING_PERIODIC_0245_DOWNLOAD_ALL=1 \
      MPCD_CUDA_STREAMING_WALL_SIMPLE_0246="$boundary_cuda" \
      MPCD_CUDA_STREAMING_WALL_SIMPLE_0246_DOWNLOAD_ALL=1 \
      MPCD_CUDA_IMMERSED_RECTANGLE_0247="$boundary_cuda" \
      MPCD_CUDA_IMMERSED_RECTANGLE_0247_DOWNLOAD_ALL=1 \
      MPCD_CUDA_STREAMING_PISTON_0247B="$boundary_cuda" \
      MPCD_CUDA_INLET_OUTLET_FULLFACE_0249A="$boundary_cuda" \
      MPCD_CUDA_INLET_OUTLET_SEGMENTED_0249B="$boundary_cuda" \
      MPCD_CUDA_CELL_MOMENTS_USE=0 \
      MPCD_CUDA_THERMOSTAT_USE=0 \
      MPCD_CUDA_THERMOSTAT_PERSISTENT_0258="$persistent_thermostat_0258" \
      MPCD_CUDA_THERMOSTAT_PERSISTENT_0258_STRICT=1 \
      MPCD_CUDA_THERMOSTAT_PERSISTENT_0258_METADATA_CACHE=1 \
      MPCD_CUDA_SRC_COLLISION_USE=0 \
      MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE="$persistent_collision" \
      MPCD_CUDA_PERSISTENT_SRC_COLLISION_STRICT=1 \
      MPCD_CUDA_PERSISTENT_SRC_COLLISION_ACTIVE_STRICT=1 \
      MPCD_CUDA_PERSISTENT_SRC_COLLISION_MINIMAL_DOWNLOAD_0257=1 \
      MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251="$collision_shared_0251" \
      MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251_STRICT=1 \
      MPCD_CUDA_PERSISTENT_SRC_COLLISION_WALL_SIMPLE_0253=0 \
      MPCD_CUDA_PERSISTENT_SRC_COLLISION_IMMERSED_RECT_0254=0 \
      MPCD_CUDA_PERSISTENT_SRC_COLLISION_PISTON_0255="$persistent_collision" \
      MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE=0 \
      MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_CONSUME_STRICT=1 \
      MPCD_CUDA_PERSISTENT_PARTICLE_STATE_USE=0 \
      MPCD_CUDA_PERSISTENT_PARTICLE_METADATA_CACHE=0 \
      MPCD_CUDA_PERSISTENT_CELL_WORKSPACE_USE=0 \
      MPCD_CUDA_PERSISTENT_THREADS_PER_BLOCK=${MPCD_CUDA_PERSISTENT_THREADS_PER_BLOCK:-256} \
      MPCD_CUDA_RESAMPLING_EXTRACTION_USE=0 \
      MPCD_CUDA_RESAMPLING_INSERTION_USE=0 \
      MPCD_CUDA_RESAMPLING_PERSISTENT_0240="$cuda_resampling" \
      MPCD_CUDA_RESAMPLING_PERSISTENT_0240_MIN_PARTICLES=0 \
      MPCD_CUDA_RESAMPLING_PERSISTENT_ACTIVE_PATH_0241_STRICT=1 \
      MPCD_CUDA_RESAMPLING_PERSISTENT_ACTIVE_PATH_0242_UPLOAD_MODE="$resampling_upload_mode" \
      MPCD_CUDA_RESAMPLING_PERSISTENT_ACTIVE_PATH_0242_DOWNLOAD_ALL="$resampling_download_all" \
      MPCD_CUDA_RESAMPLING_PERSISTENT_ACTIVE_PATH_0242_HOST_SHADOW_AUTHORITATIVE="$resampling_host_shadow" \
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
  IFS=: read -r nx ny steps extra <<<"$grid_spec"
  if [[ -n "${extra:-}" || -z "${steps:-}" ]]; then
    echo "[0278-cuda-thermostat-piston] ERROR: GRID_CASES entries must be NX:NY:STEPS, got $grid_spec" >&2
    exit 2
  fi
  grid_tag="${nx}x${ny}_s${steps}"
  for case_name in $CASES; do
    if [[ "$case_name" != "piston_virial_full" ]]; then
      echo "[0278-cuda-thermostat-piston] ERROR: 0278 is limited to piston_virial_full, got $case_name" >&2
      exit 2
    fi

    base_root="$ART_DIR/${case_name}_${BASELINE_MODE_NAME}_${grid_tag}"
    base_stdout="$ART_DIR/${case_name}_${BASELINE_MODE_NAME}_${grid_tag}.stdout.log"
    base_stderr="$ART_DIR/${case_name}_${BASELINE_MODE_NAME}_${grid_tag}.stderr.log"
    echo "[0278-cuda-thermostat-piston] running baseline case=$case_name grid=$grid_tag"
    base_rc=0
    run_validation_logged "$case_name" "$nx" "$ny" "$steps" "$base_root" "cuda_thermostat_piston_0278_${case_name}_baseline_${grid_tag}" "$BASELINE_MODE_NAME" "$base_stdout" "$base_stderr" || base_rc=$?
    base_total=$(summary_times "$base_root/validation_summary_0162.csv")

    run_root="$ART_DIR/${case_name}_${CUDA_MODE_NAME}_${grid_tag}"
    stdout_log="$ART_DIR/${case_name}_${CUDA_MODE_NAME}_${grid_tag}.stdout.log"
    stderr_log="$ART_DIR/${case_name}_${CUDA_MODE_NAME}_${grid_tag}.stderr.log"
    compare_csv="$ART_DIR/${case_name}_${CUDA_MODE_NAME}_${grid_tag}_compare.csv"
    compare_summary="$ART_DIR/${case_name}_${CUDA_MODE_NAME}_${grid_tag}_compare_summary.csv"
    echo "[0278-cuda-thermostat-piston] running CUDA thermostat case=$case_name grid=$grid_tag"
    rc=0
    run_validation_logged "$case_name" "$nx" "$ny" "$steps" "$run_root" "cuda_thermostat_piston_0278_${case_name}_${CUDA_MODE_NAME}_${grid_tag}" "$CUDA_MODE_NAME" "$stdout_log" "$stderr_log" || rc=$?
    cmp_rc=0
    compare_runs "$base_root" "$run_root" "$compare_csv" "$compare_summary" "$stdout_log" "$stderr_log" || cmp_rc=$?
    IFS=, read -r failed compared verdict <<<"$(read_compare_summary "$compare_summary")"
    if [[ "$base_rc" != "0" || "$rc" != "0" || "$cmp_rc" != "0" ]]; then verdict="FAIL"; fi
    mode_total=$(summary_times "$run_root/validation_summary_0162.csv")
    IFS=, read -r coll_calls coll_total coll_upload coll_kernel coll_download coll_shared_p coll_shared_c coll_thermo_gpu <<<"$(collision_stats "$run_root")"
    IFS=, read -r th_calls th_total th_upload th_kin th_scale th_apply th_download th_particles th_cells th_part_rescaled th_kbt_before th_kbt_after <<<"$(thermostat_stats "$run_root")"
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
      "$case_name" "$grid_tag" "$nx" "$ny" "$steps" "$CUDA_MODE_NAME" 1 "$PROJECTION_ENABLE" \
      "$RESAMPLING_ENABLE" "$USE_CUDA_RESAMPLING" 1 "$WALL_THERMAL_NOISE" 0 1 "$rc" "$cmp_rc" \
      "$base_total" "$mode_total" "$delta" "$speedup" \
      "$coll_calls" "$coll_total" "$coll_upload" "$coll_kernel" "$coll_download" "$coll_shared_p" "$coll_shared_c" "$coll_thermo_gpu" \
      "$th_calls" "$th_total" "$th_upload" "$th_kin" "$th_scale" "$th_apply" "$th_download" "$th_particles" "$th_cells" "$th_part_rescaled" \
      "$th_kbt_before" "$th_kbt_after" "$failed" "$compared" "$verdict" "$stdout_log" "$stderr_log" "$compare_csv" "$compare_summary"
    echo "[0278-cuda-thermostat-piston] $verdict case=$case_name grid=$grid_tag failed=$failed/$compared wall=$mode_total baseline=$base_total postCpuThermostatCalls=$th_calls"
    if [[ "$STOP_ON_FAIL" == "1" && ( "$base_rc" != "0" || "$rc" != "0" || "$verdict" != "PASS" ) ]]; then
      echo "[0278-cuda-thermostat-piston] stopping after failure; see $stderr_log" >&2
      exit 1
    fi
  done
done

echo "[0278-cuda-thermostat-piston] wrote $OUT_CSV"
echo "[0278-cuda-thermostat-piston] fused SRC thermostat intentionally disabled; CUDA thermostat runs after CPU Q6/resampling/capacity stages."
