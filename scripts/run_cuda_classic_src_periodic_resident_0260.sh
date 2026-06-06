#!/usr/bin/env bash
set -euo pipefail

# 0260 — periodic classic SRC CUDA resident validation/performance runner.
# This is intentionally limited to periodic boundaries. It compares the CPU
# classic baseline, the previous 0259 fused path with per-step downloads, and
# the new 0260 resident path where streaming -> collision -> thermostat remains
# on the shared CudaParticleState and host downloads are deferred to summaries.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BIN=${BIN:-build/src_mpcd_base_cuda_0260}
ART_DIR=${ART_DIR:-dev_history/artifacts/gpu_cuda_classic_src_0260}
GRID_CASES=${GRID_CASES:-"64:64:300 128:128:300"}
CASES=${CASES:-"tg_periodic_full"}
GAMMA=${GAMMA:-20}
THREADS=${THREADS:-8}
SEED_BASE=${SEED_BASE:-162060}
STOP_ON_FAIL=${STOP_ON_FAIL:-1}
FORCE_REBUILD=${FORCE_REBUILD:-1}
SUMMARY_EVERY_MODE=${SUMMARY_EVERY_MODE:-final}

BASELINE_MODE_NAME=${BASELINE_MODE_NAME:-cpu_classic}
FUSED0259_MODE_NAME=${FUSED0259_MODE_NAME:-0259_periodic_fused_download_each_step}
RESIDENT0260_MODE_NAME=${RESIDENT0260_MODE_NAME:-0260_periodic_resident_classic_cuda}

mkdir -p "$ART_DIR"

if [[ "$FORCE_REBUILD" != "0" && "$FORCE_REBUILD" != "false" && "$FORCE_REBUILD" != "FALSE" ]]; then
  echo "[0260-classic-src-periodic-resident] rebuilding $BIN (FORCE_REBUILD=$FORCE_REBUILD)"
  OUT="$BIN" CUDA_ARCH_FLAGS=${CUDA_ARCH_FLAGS:-} bash scripts/build_src_mpcd_cuda_0260.sh
elif [[ ! -x "$BIN" ]]; then
  OUT="$BIN" CUDA_ARCH_FLAGS=${CUDA_ARCH_FLAGS:-} bash scripts/build_src_mpcd_cuda_0260.sh
fi
if [[ ! -x "$BIN" ]]; then
  echo "[0260-classic-src-periodic-resident] ERROR: missing binary $BIN" >&2
  exit 127
fi

OUT_CSV=${OUT_CSV:-$ART_DIR/cuda_classic_src_periodic_resident_0260.csv}
printf 'caseName,grid,NX,NY,steps,mode,classicSrcCudaMode,residentPeriodic0260,summaryEvery,runExitCode,baselineTotalWallTime,modeTotalWallTime,totalWallDelta_s,totalWallSpeedup,baselineMaxCaseWallTime,modeMaxCaseWallTime,maxCaseWallDelta_s,maxCaseWallSpeedup,collisionActiveCalls,collisionTotalSeconds,collisionUploadSeconds,collisionKernelSeconds,collisionDownloadSeconds,collisionSharedParticleStateFraction,collisionSharedCellWorkspaceFraction,thermostatGpuAppliedFraction,failed_metrics,compared_metrics,verdict,stdoutLog,stderrLog,compareCsv,compareSummary\n' > "$OUT_CSV"

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
        with open(p, newline='') as f: rows.extend(list(csv.DictReader(f)))
    except FileNotFoundError: pass
if not rows:
    print('0,0,0,0,0,nan,nan,nan')
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
print(','.join(str(x) for x in [len(rows), s('totalSeconds'), s('uploadSeconds'), s('kernelSeconds'), s('downloadSeconds'), a('sharedParticleStateEnabled'), a('sharedCellWorkspaceEnabled'), a('thermostatAppliedOnGpu')]))
PY
}

run_validation_logged() {
  local case_name=$1 nx=$2 ny=$3 steps=$4 root=$5 tag=$6 mode=$7 stdout_log=$8 stderr_log=$9
  local summary_every
  if [[ "$SUMMARY_EVERY_MODE" == "final" ]]; then
    summary_every=$steps
  else
    summary_every=${SUMMARY_EVERY:-50}
  fi
  local seed=$((SEED_BASE + nx + ny + steps))

  local streaming=0 streaming_download=1 resident=0 persistent_thermo=0 private_particle=0 private_cell=0 shared_thermo_0260=0
  case "$mode" in
    "$BASELINE_MODE_NAME") ;;
    "$FUSED0259_MODE_NAME")
      streaming=1; streaming_download=1; persistent_thermo=1; private_particle=1; private_cell=1 ;;
    "$RESIDENT0260_MODE_NAME")
      streaming=1; streaming_download=0; resident=1; persistent_thermo=1; shared_thermo_0260=1 ;;
    *) echo "[0260-classic-src-periodic-resident] ERROR: unknown mode $mode" >&2; return 2 ;;
  esac

  rm -rf "$root"
  set +e
  env BIN="$BIN" BUILD_IF_MISSING=0 CASE_LIST="$case_name" WALL_THERMAL_NOISE=0 \
      NX="$nx" NY="$ny" GAMMA="$GAMMA" STEPS="$steps" SUMMARY_EVERY="$summary_every" \
      THREADS="$THREADS" SEED="$seed" DUMP_STATE_EVERY=0 \
      RUN_ROOT="$root" RUN_TAG="$tag" PROJECTION_BACKEND=cpu PROJECTION_ENABLE=false \
      SRC_CLASSIC_CUDA_MODE_ENABLE=true RESAMPLING_ENABLE=false THERMOSTAT_ENABLE=true \
      MPCD_CUDA_CLASSIC_SRC_PERIODIC_RESIDENT_0260="$resident" \
      MPCD_CUDA_STREAMING_PERIODIC_0245="$streaming" \
      MPCD_CUDA_STREAMING_PERIODIC_0245_DOWNLOAD_ALL="$streaming_download" \
      MPCD_CUDA_STREAMING_PERIODIC_0245_THREADS=${MPCD_CUDA_STREAMING_PERIODIC_0245_THREADS:-256} \
      MPCD_CUDA_STREAMING_WALL_SIMPLE_0246=0 \
      MPCD_CUDA_IMMERSED_RECTANGLE_0247=0 \
      MPCD_CUDA_STREAMING_PISTON_0247B=0 \
      MPCD_CUDA_INLET_OUTLET_FULLFACE_0249A=0 \
      MPCD_CUDA_INLET_OUTLET_SEGMENTED_0249B=0 \
      MPCD_CUDA_CELL_MOMENTS_USE=0 \
      MPCD_CUDA_THERMOSTAT_USE=0 \
      MPCD_CUDA_THERMOSTAT_PERSISTENT_0258=0 \
      MPCD_CUDA_SRC_COLLISION_USE=0 \
      MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=0 \
      MPCD_CUDA_PERSISTENT_SRC_COLLISION_STRICT=1 \
      MPCD_CUDA_PERSISTENT_SRC_COLLISION_ACTIVE_STRICT=1 \
      MPCD_CUDA_PERSISTENT_SRC_COLLISION_MINIMAL_DOWNLOAD_0257=0 \
      MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251=0 \
      MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE="$persistent_thermo" \
      MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_STRICT=1 \
      MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_CONSUME_STRICT=1 \
      MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260="$shared_thermo_0260" \
      MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260_STRICT=1 \
      MPCD_CUDA_PERSISTENT_PARTICLE_STATE_USE="$private_particle" \
      MPCD_CUDA_PERSISTENT_PARTICLE_METADATA_CACHE=1 \
      MPCD_CUDA_PERSISTENT_CELL_WORKSPACE_USE="$private_cell" \
      MPCD_CUDA_PERSISTENT_THREADS_PER_BLOCK=${MPCD_CUDA_PERSISTENT_THREADS_PER_BLOCK:-256} \
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
    echo "[0260-classic-src-periodic-resident] ERROR: GRID_CASES entries must be NX:NY:STEPS, got $grid_spec" >&2
    exit 2
  fi
  grid_tag="${nx}x${ny}_s${steps}"
  # Keep a CSV-visible SUMMARY_EVERY value outside run_validation_logged().
  # The local variable used inside that function is intentionally scoped there;
  # with `set -u`, referencing it here caused an unbound-variable abort.
  if [[ "$SUMMARY_EVERY_MODE" == "final" ]]; then
    summary_every_for_grid="$steps"
  else
    summary_every_for_grid="${SUMMARY_EVERY:-50}"
  fi
  for case_name in $CASES; do
    if [[ "$case_name" != "tg_periodic_full" ]]; then
      echo "[0260-classic-src-periodic-resident] ERROR: 0260 is limited to tg_periodic_full / periodic CL, got $case_name" >&2
      exit 2
    fi
    base_root="$ART_DIR/${case_name}_${BASELINE_MODE_NAME}_${grid_tag}"
    base_stdout="$ART_DIR/${case_name}_${BASELINE_MODE_NAME}_${grid_tag}.stdout.log"
    base_stderr="$ART_DIR/${case_name}_${BASELINE_MODE_NAME}_${grid_tag}.stderr.log"
    echo "[0260-classic-src-periodic-resident] running baseline case=$case_name grid=$grid_tag"
    run_validation_logged "$case_name" "$nx" "$ny" "$steps" "$base_root" "cuda_classic_src_0260_${case_name}_baseline_${grid_tag}" "$BASELINE_MODE_NAME" "$base_stdout" "$base_stderr"
    base_rc=$?
    IFS=, read -r base_total base_max <<<"$(summary_times "$base_root/validation_summary_0162.csv")"

    for mode in "$FUSED0259_MODE_NAME" "$RESIDENT0260_MODE_NAME"; do
      run_root="$ART_DIR/${case_name}_${mode}_${grid_tag}"
      stdout_log="$ART_DIR/${case_name}_${mode}_${grid_tag}.stdout.log"
      stderr_log="$ART_DIR/${case_name}_${mode}_${grid_tag}.stderr.log"
      compare_csv="$ART_DIR/${case_name}_${mode}_${grid_tag}_compare.csv"
      compare_summary="$ART_DIR/${case_name}_${mode}_${grid_tag}_compare_summary.csv"
      echo "[0260-classic-src-periodic-resident] running case=$case_name mode=$mode grid=$grid_tag"
      run_validation_logged "$case_name" "$nx" "$ny" "$steps" "$run_root" "cuda_classic_src_0260_${case_name}_${mode}_${grid_tag}" "$mode" "$stdout_log" "$stderr_log"
      rc=$?
      cmp_rc=0
      compare_runs "$base_root" "$run_root" "$compare_csv" "$compare_summary" "$stdout_log" "$stderr_log" || cmp_rc=$?
      IFS=, read -r failed compared verdict <<<"$(read_compare_summary "$compare_summary")"
      IFS=, read -r mode_total mode_max <<<"$(summary_times "$run_root/validation_summary_0162.csv")"
      IFS=, read -r coll_calls coll_total coll_upload coll_kernel coll_download coll_shared_p coll_shared_c coll_thermo_gpu <<<"$(collision_stats "$run_root")"
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
      resident_flag=0
      if [[ "$mode" == "$RESIDENT0260_MODE_NAME" ]]; then resident_flag=1; fi
      printf '%s,%s,%s,%s,%s,%s,1,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
        "$case_name" "$grid_tag" "$nx" "$ny" "$steps" "$mode" "$resident_flag" "$summary_every_for_grid" "$rc" \
        "$base_total" "$mode_total" "$delta" "$speedup" "$base_max" "$mode_max" "$max_delta" "$max_speedup" \
        "$coll_calls" "$coll_total" "$coll_upload" "$coll_kernel" "$coll_download" "$coll_shared_p" "$coll_shared_c" "$coll_thermo_gpu" \
        "$failed" "$compared" "$verdict" "$stdout_log" "$stderr_log" "$compare_csv" "$compare_summary" >> "$OUT_CSV"
      echo "[0260-classic-src-periodic-resident] $verdict case=$case_name grid=$grid_tag mode=$mode failed=$failed/$compared wall=$mode_total baseline=$base_total"
      if [[ "$STOP_ON_FAIL" == "1" && ( "$rc" != "0" || "$verdict" != "PASS" ) ]]; then
        echo "[0260-classic-src-periodic-resident] stopping after failure; see $stderr_log" >&2
        exit 1
      fi
    done
  done
done

echo "[0260-classic-src-periodic-resident] wrote $OUT_CSV"
echo "[0260-classic-src-periodic-resident] scope: periodic CL only; Q6/Q9/resampling/virial disabled; host downloads deferred to summaries in resident mode."
