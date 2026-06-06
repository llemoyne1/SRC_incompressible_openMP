#!/usr/bin/env bash
set -euo pipefail

# 0257 — performance validation of persistent CUDA SRC collision with minimal
# post-collision download. Q6/projection, thermostat, virial closure and the
# deterministic inlet reservoir remain CPU.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BIN=${BIN:-build/src_mpcd_base_cuda_0257}
ART_DIR=${ART_DIR:-dev_history/artifacts/gpu_cuda_src_collision_0257}
GRID_CASES=${GRID_CASES:-"64:64:300 128:128:300"}
CASES=${CASES:-"tg_periodic_full poiseuille_wall_full open_rect_obstacle_full piston_virial_full"}
GAMMA=${GAMMA:-20}
THREADS=${THREADS:-8}
SUMMARY_EVERY_DEFAULT=${SUMMARY_EVERY:-50}
SEED_BASE=${SEED_BASE:-162056}
PROJECTION_BACKEND=${PROJECTION_BACKEND:-cpu}
PROJECTION_ENABLE=${PROJECTION_ENABLE:-true}
STOP_ON_FAIL=${STOP_ON_FAIL:-1}

BASELINE_MODE_NAME=${BASELINE_MODE_NAME:-cpu_baseline}
CELL0251_MODE_NAME=${CELL0251_MODE_NAME:-0251_persistent_cell_moments}
COLL0257_REF_MODE_NAME=${COLL0257_REF_MODE_NAME:-0256_full_collision_download}
COLL0257_MIN_MODE_NAME=${COLL0257_MIN_MODE_NAME:-0257_minimal_collision_download}

mkdir -p "$ART_DIR"

# During CUDA patch development we want to avoid stale binaries after a small
# source-only corrective zip is applied. Rebuild by default; set FORCE_REBUILD=0
# only when explicitly reusing an already rebuilt binary.
FORCE_REBUILD=${FORCE_REBUILD:-1}
if [[ "$FORCE_REBUILD" != "0" && "$FORCE_REBUILD" != "false" && "$FORCE_REBUILD" != "FALSE" ]]; then
  echo "[0257-src-collision-min-download] rebuilding $BIN (FORCE_REBUILD=$FORCE_REBUILD)"
  OUT="$BIN" CUDA_ARCH_FLAGS=${CUDA_ARCH_FLAGS:-} bash scripts/build_src_mpcd_cuda_0257.sh
elif [[ ! -x "$BIN" ]]; then
  OUT="$BIN" CUDA_ARCH_FLAGS=${CUDA_ARCH_FLAGS:-} bash scripts/build_src_mpcd_cuda_0257.sh
fi
if [[ ! -x "$BIN" ]]; then
  echo "[0257-src-collision-min-download] ERROR: missing binary $BIN" >&2
  exit 127
fi

OUT_CSV=${OUT_CSV:-$ART_DIR/cuda_persistent_src_collision_0257.csv}
printf 'caseName,grid,NX,NY,steps,mode,resamplingCuda,boundaryStackCuda,cellMomentsCuda,persistentCellState0251,persistentSrcCollision0256,minimalCollisionDownload0257,collisionWallSimple0253,collisionImmersedRect0254,collisionPiston0255,wallThermalNoise,projectionEnable,projectionBackend,runExitCode,baselineTotalWallTime,modeTotalWallTime,totalWallDelta_s,totalWallSpeedup,baselineMaxCaseWallTime,modeMaxCaseWallTime,maxCaseWallDelta_s,maxCaseWallSpeedup,collisionActiveCalls,collisionParticlesVisitedPerCall,collisionFluidParticlesPerCall,collisionParticlesRotatedPerCall,collisionInvalidCellParticlesTotal,collisionNumCells,collisionTotalSeconds,collisionUploadSeconds,collisionKernelSeconds,collisionDownloadSeconds,collisionAvgTotalSeconds,collisionAvgKernelSeconds,collisionSharedParticleStateFraction,collisionSharedCellWorkspaceFraction,collisionParticleStateUploadSeconds,collisionCellWorkspaceAllocateSeconds,failed_metrics,compared_metrics,verdict,stdoutLog,stderrLog,compareCsv,compareSummary\n' > "$OUT_CSV"

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
    total=sum(vals) if vals else float('nan')
    mx=max(vals) if vals else float('nan')
    print(f'{total},{mx}')
except Exception:
    print('nan,nan')
PY
}

read_compare_summary() {
  local f=$1
  python3 - "$f" <<'PY'
import csv, sys
p=sys.argv[1]
failed=999999; compared=0; verdict='FAIL'
try:
    with open(p, newline='') as fh:
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
root=sys.argv[1]
paths=glob.glob(os.path.join(root, '*', 'cuda_persistent_src_collision_thermostat_0215.csv'))
rows=[]
for p in paths:
    try:
        with open(p, newline='') as f:
            rows.extend(list(csv.DictReader(f)))
    except FileNotFoundError:
        pass
if not rows:
    print('0,nan,nan,nan,0,nan,0,0,0,0,nan,nan,nan,nan,0,0')
    raise SystemExit(0)
def vals(k):
    out=[]
    for r in rows:
        try: out.append(float(r.get(k,'nan')))
        except Exception: out.append(float('nan'))
    return out
def finite(xs): return [x for x in xs if math.isfinite(x)]
def ssum(k): return sum(finite(vals(k)))
def avg(k):
    xs=finite(vals(k)); return sum(xs)/len(xs) if xs else float('nan')
calls=len(rows)
invalid=ssum('invalidCellParticles')
print(','.join(str(x) for x in [
    calls,
    avg('particlesVisited'),
    avg('fluidParticles'),
    avg('particlesRotated'),
    invalid,
    avg('numCells'),
    ssum('totalSeconds'),
    ssum('uploadSeconds'),
    ssum('kernelSeconds'),
    ssum('downloadSeconds'),
    ssum('totalSeconds')/calls if calls else float('nan'),
    ssum('kernelSeconds')/calls if calls else float('nan'),
    avg('sharedParticleStateEnabled'),
    avg('sharedCellWorkspaceEnabled'),
    ssum('particleStateUploadSeconds'),
    ssum('cellWorkspaceAllocateSeconds'),
]))
PY
}

collision_feature_flags_for_case() {
  local case_name=$1
  local wall=0 immersed=0 piston=0
  case "$case_name" in
    tg_periodic_full)
      ;;
    poiseuille_wall_full)
      wall=1 ;;
    open_rect_obstacle_full)
      immersed=1 ;;
    piston_virial_full)
      piston=1 ;;
    *)
      echo "[0257-src-collision-min-download] ERROR: unsupported case for consolidated collision validation: $case_name" >&2
      return 2 ;;
  esac
  echo "$wall,$immersed,$piston"
}

run_validation_logged() {
  local case_name=$1 nx=$2 ny=$3 steps=$4 root=$5 tag=$6 mode=$7 stdout_log=$8 stderr_log=$9
  local summary_every=${SUMMARY_EVERY_OVERRIDE:-$SUMMARY_EVERY_DEFAULT}
  local seed=$((SEED_BASE + nx + ny + steps))

  local resampling_cuda=0
  local resampling_download_all=1
  local resampling_host_shadow=0
  local resampling_upload_mode=all
  local boundary_cuda=0
  local cell_cuda=0
  local persistent_cell=0
  local persistent_collision=0
  local collision_shared_0251=0
  local minimal_download_0257=0
  local coll_wall=0 coll_immersed=0 coll_piston=0

  case "$mode" in
    "$BASELINE_MODE_NAME")
      ;;
    "$CELL0251_MODE_NAME")
      resampling_cuda=1; resampling_download_all=0; resampling_host_shadow=1; resampling_upload_mode=roles_only
      boundary_cuda=1; cell_cuda=1; persistent_cell=1 ;;
    "$COLL0257_REF_MODE_NAME")
      resampling_cuda=1; resampling_download_all=0; resampling_host_shadow=1; resampling_upload_mode=roles_only
      boundary_cuda=1; cell_cuda=0; persistent_cell=0
      persistent_collision=1; collision_shared_0251=1
      IFS=, read -r coll_wall coll_immersed coll_piston <<<"$(collision_feature_flags_for_case "$case_name")" ;;
    "$COLL0257_MIN_MODE_NAME")
      resampling_cuda=1; resampling_download_all=0; resampling_host_shadow=1; resampling_upload_mode=roles_only
      boundary_cuda=1; cell_cuda=0; persistent_cell=0
      persistent_collision=1; collision_shared_0251=1; minimal_download_0257=1
      IFS=, read -r coll_wall coll_immersed coll_piston <<<"$(collision_feature_flags_for_case "$case_name")" ;;
    *) echo "[0257-src-collision-min-download] ERROR: unknown mode $mode" >&2; return 2 ;;
  esac

  rm -rf "$root"
  set +e
  env BIN="$BIN" BUILD_IF_MISSING=0 CASE_LIST="$case_name" WALL_THERMAL_NOISE="${WALL_THERMAL_NOISE:-0}" \
      NX="$nx" NY="$ny" GAMMA="$GAMMA" STEPS="$steps" SUMMARY_EVERY="$summary_every" \
      THREADS="$THREADS" SEED="$seed" DUMP_STATE_EVERY=0 \
      RUN_ROOT="$root" RUN_TAG="$tag" PROJECTION_BACKEND="$PROJECTION_BACKEND" PROJECTION_ENABLE="$PROJECTION_ENABLE" \
      MPCD_CUDA_CELL_MOMENTS_USE="$cell_cuda" \
      MPCD_CUDA_CELL_MOMENTS_REUSE_BUFFERS=${MPCD_CUDA_CELL_MOMENTS_REUSE_BUFFERS:-1} \
      MPCD_CUDA_CELL_MOMENTS_ALL_FLUID_FASTPATH=${MPCD_CUDA_CELL_MOMENTS_ALL_FLUID_FASTPATH:-1} \
      MPCD_CUDA_CELL_MOMENTS_UNIFORM_MASS_FASTPATH=${MPCD_CUDA_CELL_MOMENTS_UNIFORM_MASS_FASTPATH:-1} \
      MPCD_CUDA_CELL_MOMENTS_THREADS_PER_BLOCK=${MPCD_CUDA_CELL_MOMENTS_THREADS_PER_BLOCK:-256} \
      MPCD_CUDA_CELL_MOMENTS_SHADOW=0 \
      MPCD_CUDA_CELL_MOMENTS_PERSISTENT_STATE_0251="$persistent_cell" \
      MPCD_CUDA_THERMOSTAT_USE=0 \
      MPCD_CUDA_SRC_COLLISION_USE=0 \
      MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE="$persistent_collision" \
      MPCD_CUDA_PERSISTENT_SRC_COLLISION_STRICT=1 \
      MPCD_CUDA_PERSISTENT_SRC_COLLISION_ACTIVE_STRICT=1 \
      MPCD_CUDA_PERSISTENT_SRC_COLLISION_MINIMAL_DOWNLOAD_0257="$minimal_download_0257" \
      MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251="$collision_shared_0251" \
      MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251_STRICT=1 \
      MPCD_CUDA_PERSISTENT_SRC_COLLISION_WALL_SIMPLE_0253="$coll_wall" \
      MPCD_CUDA_PERSISTENT_SRC_COLLISION_IMMERSED_RECT_0254="$coll_immersed" \
      MPCD_CUDA_PERSISTENT_SRC_COLLISION_PISTON_0255="$coll_piston" \
      MPCD_CUDA_PERSISTENT_THREADS_PER_BLOCK=${MPCD_CUDA_PERSISTENT_THREADS_PER_BLOCK:-256} \
      MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE=0 \
      MPCD_CUDA_PERSISTENT_PARTICLE_STATE_USE=0 \
      MPCD_CUDA_PERSISTENT_PARTICLE_METADATA_CACHE=0 \
      MPCD_CUDA_PERSISTENT_CELL_WORKSPACE_USE=0 \
      MPCD_CUDA_RESAMPLING_EXTRACTION_USE=0 \
      MPCD_CUDA_RESAMPLING_INSERTION_USE=0 \
      MPCD_CUDA_RESAMPLING_PERSISTENT_0240="$resampling_cuda" \
      MPCD_CUDA_RESAMPLING_PERSISTENT_0240_MIN_PARTICLES=0 \
      MPCD_CUDA_RESAMPLING_PERSISTENT_ACTIVE_PATH_0241_STRICT=1 \
      MPCD_CUDA_RESAMPLING_PERSISTENT_ACTIVE_PATH_0242_UPLOAD_MODE="$resampling_upload_mode" \
      MPCD_CUDA_RESAMPLING_PERSISTENT_ACTIVE_PATH_0242_DOWNLOAD_ALL="$resampling_download_all" \
      MPCD_CUDA_RESAMPLING_PERSISTENT_ACTIVE_PATH_0242_HOST_SHADOW_AUTHORITATIVE="$resampling_host_shadow" \
      MPCD_CUDA_STREAMING_PERIODIC_0245="$boundary_cuda" \
      MPCD_CUDA_STREAMING_PERIODIC_0245_THREADS="${MPCD_CUDA_STREAMING_PERIODIC_0245_THREADS:-256}" \
      MPCD_CUDA_STREAMING_WALL_SIMPLE_0246="$boundary_cuda" \
      MPCD_CUDA_STREAMING_WALL_SIMPLE_0246_THREADS="${MPCD_CUDA_STREAMING_WALL_SIMPLE_0246_THREADS:-256}" \
      MPCD_CUDA_IMMERSED_RECTANGLE_0247="$boundary_cuda" \
      MPCD_CUDA_IMMERSED_RECTANGLE_0247_THREADS="${MPCD_CUDA_IMMERSED_RECTANGLE_0247_THREADS:-256}" \
      MPCD_CUDA_STREAMING_PISTON_0247B="$boundary_cuda" \
      MPCD_CUDA_STREAMING_PISTON_0247B_THREADS="${MPCD_CUDA_STREAMING_PISTON_0247B_THREADS:-256}" \
      MPCD_CUDA_INLET_OUTLET_FULLFACE_0249A="$boundary_cuda" \
      MPCD_CUDA_INLET_OUTLET_SEGMENTED_0249B="$boundary_cuda" \
      MPCD_CUDA_INLET_OUTLET_FULLFACE_0249A_THREADS="${MPCD_CUDA_INLET_OUTLET_FULLFACE_0249A_THREADS:-256}" \
      MPCD_CUDA_INLET_OUTLET_SEGMENTED_0249B_THREADS="${MPCD_CUDA_INLET_OUTLET_SEGMENTED_0249B_THREADS:-256}" \
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
  return 99
}

for spec in $GRID_CASES; do
  IFS=':' read -r nx ny steps extra <<<"$spec"
  if [[ -n "${extra:-}" || -z "${nx:-}" || -z "${ny:-}" ]]; then
    echo "[0257-src-collision-min-download] ERROR: GRID_CASES entries must be NX:NY:STEPS, got '$spec'" >&2
    exit 2
  fi
  if [[ -z "${steps:-}" ]]; then steps=300; fi
  label="${nx}x${ny}_s${steps}"

  for case_name in $CASES; do
    echo "[0257-src-collision-min-download] running baseline case=$case_name grid=$label"
    base_root="runs/cuda_src_collision_0257_${case_name}_baseline_${label}"
    base_stdout="$ART_DIR/baseline_${case_name}_${label}.stdout.log"
    base_stderr="$ART_DIR/baseline_${case_name}_${label}.stderr.log"
    base_rc=0
    run_validation_logged "$case_name" "$nx" "$ny" "$steps" "$base_root" "baseline_${case_name}_${label}" "$BASELINE_MODE_NAME" "$base_stdout" "$base_stderr" || base_rc=$?
    IFS=, read -r base_total base_max <<<"$(summary_times "$base_root/validation_summary_0162.csv")"

    for mode in "$CELL0251_MODE_NAME" "$COLL0257_REF_MODE_NAME" "$COLL0257_MIN_MODE_NAME"; do
      echo "[0257-src-collision-min-download] running case=$case_name mode=$mode grid=$label"
      run_root="runs/cuda_src_collision_0257_${case_name}_${mode}_${label}"
      stdout_log="$ART_DIR/${case_name}_${mode}_${label}.stdout.log"
      stderr_log="$ART_DIR/${case_name}_${mode}_${label}.stderr.log"
      rc=0
      run_validation_logged "$case_name" "$nx" "$ny" "$steps" "$run_root" "${case_name}_${mode}_${label}" "$mode" "$stdout_log" "$stderr_log" || rc=$?
      IFS=, read -r mode_total mode_max <<<"$(summary_times "$run_root/validation_summary_0162.csv")"
      compare_csv="$ART_DIR/compare_${case_name}_${mode}_${label}.csv"
      compare_summary="$ART_DIR/compare_summary_${case_name}_${mode}_${label}.csv"
      cmp_rc=0
      compare_runs "$base_root" "$run_root" "$compare_csv" "$compare_summary" "$stdout_log" "$stderr_log" || cmp_rc=$?
      IFS=, read -r failed compared verdict <<<"$(read_compare_summary "$compare_summary")"
      if [[ $rc -ne 0 || $base_rc -ne 0 || $cmp_rc -ne 0 ]]; then verdict="FAIL"; fi
      IFS=, read -r coll_calls coll_particles coll_fluid coll_rotated coll_invalid coll_cells coll_total coll_upload coll_kernel coll_download coll_avg_total coll_avg_kernel coll_shared_p coll_shared_c coll_p_upload coll_c_alloc <<<"$(collision_stats "$run_root")"

      row_resampling_cuda=0
      row_boundary_cuda=0
      row_cell_cuda=0
      row_persistent_cell=0
      row_persistent_collision=0
      row_minimal_download_0257=0
      row_wall=0
      row_immersed=0
      row_piston=0
      case "$mode" in
        "$CELL0251_MODE_NAME")
          row_resampling_cuda=1; row_boundary_cuda=1; row_cell_cuda=1; row_persistent_cell=1 ;;
        "$COLL0257_REF_MODE_NAME")
          row_resampling_cuda=1; row_boundary_cuda=1; row_cell_cuda=0; row_persistent_collision=1
          IFS=, read -r row_wall row_immersed row_piston <<<"$(collision_feature_flags_for_case "$case_name")" ;;
        "$COLL0257_MIN_MODE_NAME")
          row_resampling_cuda=1; row_boundary_cuda=1; row_cell_cuda=0; row_persistent_collision=1; row_minimal_download_0257=1
          IFS=, read -r row_wall row_immersed row_piston <<<"$(collision_feature_flags_for_case "$case_name")" ;;
      esac

      python3 - "$OUT_CSV" "$case_name" "$label" "$nx" "$ny" "$steps" "$mode" \
        "$row_resampling_cuda" "$row_boundary_cuda" "$row_cell_cuda" "$row_persistent_cell" "$row_persistent_collision" \
        "$row_minimal_download_0257" "$row_wall" "$row_immersed" "$row_piston" "${WALL_THERMAL_NOISE:-0}" \
        "$PROJECTION_ENABLE" "$PROJECTION_BACKEND" "$rc" "$base_total" "$mode_total" "$base_max" "$mode_max" \
        "$coll_calls" "$coll_particles" "$coll_fluid" "$coll_rotated" "$coll_invalid" "$coll_cells" \
        "$coll_total" "$coll_upload" "$coll_kernel" "$coll_download" "$coll_avg_total" "$coll_avg_kernel" \
        "$coll_shared_p" "$coll_shared_c" "$coll_p_upload" "$coll_c_alloc" "$failed" "$compared" "$verdict" \
        "$stdout_log" "$stderr_log" "$compare_csv" "$compare_summary" <<'PY'
import csv, math, sys
(out, caseName, label, nx, ny, steps, mode,
 resamplingCuda, boundaryCuda, cellCuda, persistentCell, persistentCollision, minimalDownload0257,
 collWall, collImmersed, collPiston, wallThermalNoise,
 projectionEnable, projectionBackend, rc, baseTotal, modeTotal, baseMax, modeMax,
 collCalls, collParticles, collFluid, collRotated, collInvalid, collCells,
 collTotal, collUpload, collKernel, collDownload, collAvgTotal, collAvgKernel,
 collSharedP, collSharedC, collPUpload, collCAlloc, failed, compared, verdict,
 stdoutLog, stderrLog, compareCsv, compareSummary) = sys.argv[1:]
def f(x):
    try: return float(x)
    except Exception: return float('nan')
bt, mt, bm, mm = map(f, (baseTotal, modeTotal, baseMax, modeMax))
row=[caseName,label,nx,ny,steps,mode,resamplingCuda,boundaryCuda,cellCuda,persistentCell,persistentCollision,minimalDownload0257,
     collWall,collImmersed,collPiston,wallThermalNoise,projectionEnable,projectionBackend,rc,baseTotal,modeTotal,
     mt-bt if math.isfinite(mt) and math.isfinite(bt) else float('nan'),
     bt/mt if math.isfinite(mt) and mt>0 and math.isfinite(bt) else float('nan'),
     baseMax,modeMax,
     mm-bm if math.isfinite(mm) and math.isfinite(bm) else float('nan'),
     bm/mm if math.isfinite(mm) and mm>0 and math.isfinite(bm) else float('nan'),
     collCalls,collParticles,collFluid,collRotated,collInvalid,collCells,
     collTotal,collUpload,collKernel,collDownload,collAvgTotal,collAvgKernel,
     collSharedP,collSharedC,collPUpload,collCAlloc,failed,compared,verdict,
     stdoutLog,stderrLog,compareCsv,compareSummary]
with open(out,'a',newline='') as fh:
    csv.writer(fh).writerow(row)
PY
      echo "[0257-src-collision-min-download] $verdict case=$case_name grid=$label mode=$mode failed=$failed/$compared wall=$mode_total baseline=$base_total"
      if [[ "$STOP_ON_FAIL" == "1" && "$verdict" != "PASS" ]]; then
        echo "[0257-src-collision-min-download] stopping after failure; see $stderr_log" >&2
        exit 1
      fi
    done
  done
done

echo "[0257-src-collision-min-download] wrote $OUT_CSV"
echo "[0257-src-collision-min-download] Q6/Q9, thermostat, virial closure and inlet reservoir stayed CPU; 0257 only skips non-essential cell-field downloads after CUDA collision."
