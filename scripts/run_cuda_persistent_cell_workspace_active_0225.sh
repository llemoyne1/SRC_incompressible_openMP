#!/usr/bin/env bash
set -euo pipefail

# 0225 — compare the real persistent SRC+thermostat path with:
#   1) legacy internal upload/buffers,
#   2) shared CudaParticleState only,
#   3) shared CudaParticleState + shared CudaCellWorkspace.
# Physics subset: periodic TG, projection disabled, no wallVP/solid/capacity.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BIN=${BIN:-build/src_mpcd_base_cuda_0225}
ART_DIR=${ART_DIR:-dev_history/artifacts/gpu_cuda_persistent_0225}
GRID_CASES=${GRID_CASES:-"64:200 128:100"}
GAMMA=${GAMMA:-20}
THREADS=${THREADS:-8}
SUMMARY_EVERY_DEFAULT=${SUMMARY_EVERY:-50}
SEED_BASE=${SEED_BASE:-1620225}
PROJECTION_BACKEND=${PROJECTION_BACKEND:-cpu}
PROJECTION_ENABLE=${PROJECTION_ENABLE:-false}
CASE_LIST=${CASE_LIST:-tg_periodic_full}
MODES=${MODES:-"legacy_internal_upload shared_particle_state shared_particle_cell_workspace"}

mkdir -p "$ART_DIR"

if [[ ! -x "$BIN" ]]; then
  OUT="$BIN" CUDA_ARCH_FLAGS=${CUDA_ARCH_FLAGS:-} bash scripts/build_src_mpcd_cuda_0225.sh
fi
if [[ ! -x "$BIN" ]]; then
  echo "[0225-cell-workspace-active] ERROR: CUDA-enabled binary not found after build: $BIN" >&2
  exit 127
fi

OUT_CSV=${OUT_CSV:-$ART_DIR/cuda_persistent_cell_workspace_active_0225.csv}
printf 'grid,NX,NY,steps,mode,case,baselineWallTime,modeWallTime,wallDelta_s,wallSpeedup,failed_metrics,compared_metrics,verdict,activeCalls,totalActiveSeconds,uploadSeconds,kernelSeconds,downloadSeconds,particleStateAllocateSeconds,particleStateUploadSeconds,particleStateAllocationCalls,particleStateReusedAllocationFraction,sharedParticleStateFraction,particleStateHostToDeviceBytes,particleStateMetadataUploadCalls,particleStateMetadataCacheHits,particleStateMetadataBytesSkipped,particleStateMetadataCacheHitFraction,sharedCellWorkspaceFraction,cellWorkspaceAllocateSeconds,cellWorkspaceAllocationCalls,cellWorkspaceReusedAllocationFraction,cellWorkspaceAllocatedBytes,thermostatAppliedCalls,thermostatKBTAfterLast,activeCsv,compareCsv,compareSummary\n' > "$OUT_CSV"

append_mode_summary() {
  local label=$1 nx=$2 ny=$3 steps=$4 mode=$5 case_name=$6 baseline_summary=$7 mode_summary=$8 active_csv=$9 compare_csv=${10} compare_summary=${11}
  python3 - "$label" "$nx" "$ny" "$steps" "$mode" "$case_name" "$baseline_summary" "$mode_summary" "$active_csv" "$compare_csv" "$compare_summary" "$OUT_CSV" <<'PY'
import csv, sys, math
(label,nx,ny,steps,mode,case_name,baseline_summary,mode_summary,active_csv,compare_csv,compare_summary,out_csv)=sys.argv[1:13]

def read_one(path):
    with open(path, newline='') as f:
        rows=list(csv.DictReader(f))
    if len(rows)!=1:
        raise SystemExit(f"expected one row in {path}, got {len(rows)}")
    return rows[0]

def f(row,key,default='nan'):
    try: return float(row.get(key,default))
    except Exception: return float('nan')

def i(row,key,default='0'):
    try: return int(round(float(row.get(key,default))))
    except Exception: return 0

def truth(row,key):
    return 1.0 if str(row.get(key,'0')) not in ('0','0.0','','false','False') else 0.0

base=read_one(baseline_summary)
mode_row=read_one(mode_summary)
cmp=read_one(compare_summary)
with open(active_csv, newline='') as fp:
    rows=list(csv.DictReader(fp))
if not rows:
    raise SystemExit(f"empty active CSV: {active_csv}")

def vals(key):
    out=[]
    for r in rows:
        try: out.append(float(r.get(key,'nan')))
        except Exception: out.append(float('nan'))
    return out

def last(key):
    try: return float(rows[-1].get(key,'nan'))
    except Exception: return float('nan')

def sum_i(key):
    return sum(i(r,key,'0') for r in rows)

def frac(key):
    v=[truth(r,key) for r in rows]
    return sum(v)/len(v) if v else 0.0

base_wall=f(base,'wallTime')
mode_wall=f(mode_row,'wallTime')
failed=i(cmp,'failed_metrics','999999')
compared=i(cmp,'compared_metrics','0')
invalid=sum_i('invalidCellParticles')
verdict='PASS' if failed==0 and invalid==0 else 'FAIL'
cache_hits=sum_i('particleStateMetadataCacheHits')
row={
    'grid':label,
    'NX':nx,
    'NY':ny,
    'steps':steps,
    'mode':mode,
    'case':case_name,
    'baselineWallTime':base_wall,
    'modeWallTime':mode_wall,
    'wallDelta_s':mode_wall-base_wall,
    'wallSpeedup':base_wall/mode_wall if mode_wall>0 else float('nan'),
    'failed_metrics':failed,
    'compared_metrics':compared,
    'verdict':verdict,
    'activeCalls':len(rows),
    'totalActiveSeconds':sum(vals('totalSeconds')),
    'uploadSeconds':sum(vals('uploadSeconds')),
    'kernelSeconds':sum(vals('kernelSeconds')),
    'downloadSeconds':sum(vals('downloadSeconds')),
    'particleStateAllocateSeconds':sum(vals('particleStateAllocateSeconds')),
    'particleStateUploadSeconds':sum(vals('particleStateUploadSeconds')),
    'particleStateAllocationCalls':sum_i('particleStateAllocationCalls'),
    'particleStateReusedAllocationFraction':frac('particleStateReusedAllocation'),
    'sharedParticleStateFraction':frac('sharedParticleStateEnabled'),
    'particleStateHostToDeviceBytes':sum_i('particleStateHostToDeviceBytes'),
    'particleStateMetadataUploadCalls':sum_i('particleStateMetadataUploadCalls'),
    'particleStateMetadataCacheHits':cache_hits,
    'particleStateMetadataBytesSkipped':sum_i('particleStateMetadataBytesSkipped'),
    'particleStateMetadataCacheHitFraction':cache_hits/len(rows) if rows else 0.0,
    'sharedCellWorkspaceFraction':frac('sharedCellWorkspaceEnabled'),
    'cellWorkspaceAllocateSeconds':sum(vals('cellWorkspaceAllocateSeconds')),
    'cellWorkspaceAllocationCalls':sum_i('cellWorkspaceAllocationCalls'),
    'cellWorkspaceReusedAllocationFraction':frac('cellWorkspaceReusedAllocation'),
    'cellWorkspaceAllocatedBytes':sum_i('cellWorkspaceAllocatedBytes'),
    'thermostatAppliedCalls':sum(1 for r in rows if str(r.get('thermostatAppliedOnGpu','0')) not in ('0','0.0','')),
    'thermostatKBTAfterLast':last('thermostatKBTAfter'),
    'activeCsv':active_csv,
    'compareCsv':compare_csv,
    'compareSummary':compare_summary,
}
fieldnames=['grid','NX','NY','steps','mode','case','baselineWallTime','modeWallTime','wallDelta_s','wallSpeedup','failed_metrics','compared_metrics','verdict','activeCalls','totalActiveSeconds','uploadSeconds','kernelSeconds','downloadSeconds','particleStateAllocateSeconds','particleStateUploadSeconds','particleStateAllocationCalls','particleStateReusedAllocationFraction','sharedParticleStateFraction','particleStateHostToDeviceBytes','particleStateMetadataUploadCalls','particleStateMetadataCacheHits','particleStateMetadataBytesSkipped','particleStateMetadataCacheHitFraction','sharedCellWorkspaceFraction','cellWorkspaceAllocateSeconds','cellWorkspaceAllocationCalls','cellWorkspaceReusedAllocationFraction','cellWorkspaceAllocatedBytes','thermostatAppliedCalls','thermostatKBTAfterLast','activeCsv','compareCsv','compareSummary']
with open(out_csv,'a',newline='') as fcsv:
    w=csv.DictWriter(fcsv, fieldnames=fieldnames)
    w.writerow(row)
print(f"[0225-cell-workspace-active] {verdict} {label}/{mode}/{case_name}: wall={mode_wall:.6g}s baseline={base_wall:.6g}s speedup={row['wallSpeedup']:.4g} sharedP={row['sharedParticleStateFraction']:.2f} sharedC={row['sharedCellWorkspaceFraction']:.2f} reusedC={row['cellWorkspaceReusedAllocationFraction']:.2f} metaHit={row['particleStateMetadataCacheHitFraction']:.2f} failed={failed}/{compared}")
if verdict != 'PASS':
    raise SystemExit(1)
PY
}

run_mode() {
  local mode=$1 nx=$2 ny=$3 steps=$4 label=$5 seed=$6 summary_every=$7 baseline_root=$8
  local run_root="runs/cuda_persistent_cell_workspace_0225_${mode}_${label}"
  local shared_particle=0 metadata_cache=1 shared_cell=0
  case "$mode" in
    legacy_internal_upload) shared_particle=0; metadata_cache=0; shared_cell=0 ;;
    shared_particle_state) shared_particle=1; metadata_cache=1; shared_cell=0 ;;
    shared_particle_cell_workspace) shared_particle=1; metadata_cache=1; shared_cell=1 ;;
    *) echo "[0225-cell-workspace-active] ERROR: unknown mode $mode" >&2; exit 2 ;;
  esac

  echo "[0225-cell-workspace-active] mode=$mode $label"
  env BIN="$BIN" BUILD_IF_MISSING=0 CASE_LIST="$CASE_LIST" \
      NX="$nx" NY="$ny" GAMMA="$GAMMA" STEPS="$steps" SUMMARY_EVERY="$summary_every" \
      THREADS="$THREADS" SEED="$seed" DUMP_STATE_EVERY=0 \
      RUN_ROOT="$run_root" RUN_TAG="cuda0225_${mode}_${label}" PROJECTION_BACKEND="$PROJECTION_BACKEND" PROJECTION_ENABLE="$PROJECTION_ENABLE" \
      MPCD_CUDA_CELL_MOMENTS_USE=0 \
      MPCD_CUDA_THERMOSTAT_USE=0 \
      MPCD_CUDA_SRC_COLLISION_USE=0 \
      MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=0 \
      MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE=1 \
      MPCD_CUDA_PERSISTENT_PARTICLE_STATE_USE="$shared_particle" \
      MPCD_CUDA_PERSISTENT_PARTICLE_METADATA_CACHE="$metadata_cache" \
      MPCD_CUDA_PERSISTENT_CELL_WORKSPACE_USE="$shared_cell" \
      MPCD_CUDA_PERSISTENT_THREADS_PER_BLOCK=${MPCD_CUDA_PERSISTENT_THREADS_PER_BLOCK:-256} \
      bash scripts/run_validation_mono_config_0162.sh

  local compare_csv="$ART_DIR/cuda_persistent_cell_workspace_compare_0225_${mode}_${label}.csv"
  local compare_summary="$ART_DIR/cuda_persistent_cell_workspace_compare_summary_0225_${mode}_${label}.csv"
  python3 scripts/compare_validation_mono_config_0162.py \
    --origin "$baseline_root" \
    --optimized "$run_root" \
    --out "$compare_csv" \
    --summary-out "$compare_summary"

  local case_name
  for case_name in $CASE_LIST; do
    local active_csv="$run_root/$case_name/cuda_persistent_src_collision_thermostat_0215.csv"
    if [[ ! -f "$active_csv" ]]; then
      echo "[0225-cell-workspace-active] ERROR: missing $active_csv" >&2
      exit 3
    fi
    append_mode_summary "$label" "$nx" "$ny" "$steps" "$mode" "$case_name" \
      "$baseline_root/validation_summary_0162.csv" "$run_root/validation_summary_0162.csv" \
      "$active_csv" "$compare_csv" "$compare_summary"
  done
}

run_one() {
  local nx=$1 steps=$2 ny=${NY_OVERRIDE:-$nx}
  local label="${nx}x${ny}_s${steps}"
  local seed=$((SEED_BASE + nx + steps))
  local summary_every=${SUMMARY_EVERY_OVERRIDE:-$SUMMARY_EVERY_DEFAULT}
  local baseline_root="runs/cuda_persistent_cell_workspace_0225_cpu_baseline_${label}"

  echo "[0225-cell-workspace-active] baseline $label"
  env BIN="$BIN" BUILD_IF_MISSING=0 CASE_LIST="$CASE_LIST" \
      NX="$nx" NY="$ny" GAMMA="$GAMMA" STEPS="$steps" SUMMARY_EVERY="$summary_every" \
      THREADS="$THREADS" SEED="$seed" DUMP_STATE_EVERY=0 \
      RUN_ROOT="$baseline_root" RUN_TAG="cuda0225_cpu_baseline_${label}" PROJECTION_BACKEND="$PROJECTION_BACKEND" PROJECTION_ENABLE="$PROJECTION_ENABLE" \
      MPCD_CUDA_CELL_MOMENTS_USE=0 \
      MPCD_CUDA_THERMOSTAT_USE=0 \
      MPCD_CUDA_SRC_COLLISION_USE=0 \
      MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=0 \
      MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE=0 \
      MPCD_CUDA_PERSISTENT_PARTICLE_STATE_USE=0 \
      MPCD_CUDA_PERSISTENT_PARTICLE_METADATA_CACHE=0 \
      MPCD_CUDA_PERSISTENT_CELL_WORKSPACE_USE=0 \
      bash scripts/run_validation_mono_config_0162.sh

  local mode
  for mode in $MODES; do
    run_mode "$mode" "$nx" "$ny" "$steps" "$label" "$seed" "$summary_every" "$baseline_root"
  done
}

for item in $GRID_CASES; do
  IFS=':' read -r nx steps <<< "$item"
  if [[ -z "${nx:-}" || -z "${steps:-}" ]]; then
    echo "[0225-cell-workspace-active] malformed GRID_CASES entry: $item" >&2
    exit 2
  fi
  run_one "$nx" "$steps"
done

echo "[0225-cell-workspace-active] wrote $OUT_CSV"
