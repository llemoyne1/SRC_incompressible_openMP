#!/usr/bin/env bash
set -euo pipefail

# 0226 — combine the active shared CudaParticleState+CudaCellWorkspace
# collision-only path with CUDA Q6, preserving the physical order:
#   SRC collision -> Q6 projection -> CPU thermostat.
# This is the first harness that uses the shared cell workspace in a Q6-enabled
# run. It deliberately does not use the persistent SRC+thermostat path, because
# that would thermostat before Q6 and change the algorithm.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BIN=${BIN:-build/src_mpcd_base_cuda_0226}
ART_DIR=${ART_DIR:-dev_history/artifacts/gpu_cuda_persistent_0226}
GRID_CASES=${GRID_CASES:-"64:200 128:100"}
GAMMA=${GAMMA:-20}
THREADS=${THREADS:-8}
SUMMARY_EVERY_DEFAULT=${SUMMARY_EVERY:-50}
SEED_BASE=${SEED_BASE:-1620226}
BATCH_SIZE=${BATCH_SIZE:-20}
CASE_LIST=${CASE_LIST:-tg_periodic_full}
STOP_ON_FAIL=${STOP_ON_FAIL:-0}
# Modes:
#   cpu_baseline                CPU collision + CPU Q6 + CPU thermostat
#   q6_cuda                     CPU collision + CUDA Q6 + CPU thermostat
#   shared_collision            shared GPU particle+cell collision + CPU Q6 + CPU thermostat
#   shared_collision_q6_cuda    shared GPU particle+cell collision + CUDA Q6 + CPU thermostat
MODES=${MODES:-"cpu_baseline q6_cuda shared_collision shared_collision_q6_cuda"}

mkdir -p "$ART_DIR"

if [[ ! -x "$BIN" ]]; then
  OUT="$BIN" CUDA_ARCH_FLAGS=${CUDA_ARCH_FLAGS:-} bash scripts/build_src_mpcd_cuda_0226.sh
fi
if [[ ! -x "$BIN" ]]; then
  echo "[0226-cell-workspace-q6] ERROR: missing binary $BIN" >&2
  exit 127
fi

OUT_CSV=${OUT_CSV:-$ART_DIR/cuda_persistent_cell_workspace_q6_0226.csv}
printf 'grid,NX,NY,steps,mode,batchSize,baselineWallTime,modeWallTime,wallDelta_s,wallSpeedup,failed_metrics,compared_metrics,verdict,q6Iterations,q6DivAfterProjectedFluxRms,persistentActiveCalls,totalActiveSeconds,uploadSeconds,kernelSeconds,downloadSeconds,particleStateUploadSeconds,particleStateReusedAllocationFraction,sharedParticleStateFraction,particleStateMetadataCacheHitFraction,sharedCellWorkspaceFraction,cellWorkspaceReusedAllocationFraction,invalidCellParticles,cudaTimingSolves,cudaTimingIterations,cudaTimingBatches,cudaTimingConvergenceDownloads,cudaTimingTotalSeconds,cudaTimingHostReductionSeconds,activeCsv,compareCsv,compareSummary\n' > "$OUT_CSV"

mode_flags() {
  local mode=$1
  case "$mode" in
    cpu_baseline)              echo "cpu 0 0 0" ;;
    q6_cuda)                   echo "cuda 0 0 0" ;;
    shared_collision)          echo "cpu 1 1 1" ;;
    shared_collision_q6_cuda)  echo "cuda 1 1 1" ;;
    *) echo "[0226-cell-workspace-q6] ERROR: unknown mode $mode" >&2; return 2 ;;
  esac
}

run_validation() {
  local nx=$1 ny=$2 steps=$3 root=$4 tag=$5 projection=$6 persistent_collision=$7 shared_particle=$8 shared_cell=$9
  local summary_every=${SUMMARY_EVERY_OVERRIDE:-$SUMMARY_EVERY_DEFAULT}
  local seed=$((SEED_BASE + nx + steps))
  env BIN="$BIN" BUILD_IF_MISSING=0 CASE_LIST="$CASE_LIST" \
      NX="$nx" NY="$ny" GAMMA="$GAMMA" STEPS="$steps" SUMMARY_EVERY="$summary_every" \
      THREADS="$THREADS" SEED="$seed" DUMP_STATE_EVERY=0 \
      RUN_ROOT="$root" RUN_TAG="$tag" PROJECTION_BACKEND="$projection" PROJECTION_ENABLE=true \
      MPCD_CUDA_CELL_MOMENTS_USE=0 \
      MPCD_CUDA_THERMOSTAT_USE=0 \
      MPCD_CUDA_SRC_COLLISION_USE=0 \
      MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE="$persistent_collision" \
      MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE=0 \
      MPCD_CUDA_PERSISTENT_PARTICLE_STATE_USE="$shared_particle" \
      MPCD_CUDA_PERSISTENT_PARTICLE_METADATA_CACHE=1 \
      MPCD_CUDA_PERSISTENT_CELL_WORKSPACE_USE="$shared_cell" \
      MPCD_CUDA_PERSISTENT_THREADS_PER_BLOCK=${MPCD_CUDA_PERSISTENT_THREADS_PER_BLOCK:-256} \
      MPCD_CUDA_Q6_TIMING=1 \
      MPCD_CUDA_Q6_DISABLE_PLAN_CACHE=0 \
      MPCD_CUDA_Q6_DEVICE_SCALAR_CG=1 \
      MPCD_CUDA_Q6_LEGACY_HOST_SCALAR_CG=0 \
      MPCD_CUDA_Q6_DEVICE_SCALAR_BATCH="$BATCH_SIZE" \
      MPCD_CUDA_Q6_DEVICE_SCALAR_REDUCTION=0 \
      MPCD_CUDA_Q6_HOST_BLOCK_SUM=1 \
      MPCD_CUDA_Q6_RESIDUAL_NORM_SHORTCUT=0 \
      MPCD_CUDA_Q6_LEGACY_MEAN_REMOVAL_RESIDUAL_NORM=1 \
      bash scripts/run_validation_mono_config_0162.sh
}

append_summary() {
  local label=$1 nx=$2 ny=$3 steps=$4 mode=$5 base_root=$6 run_root=$7 compare_csv=$8 compare_summary=$9
  python3 - "$label" "$nx" "$ny" "$steps" "$mode" "$BATCH_SIZE" "$base_root/validation_summary_0162.csv" "$run_root/validation_summary_0162.csv" "$run_root" "$compare_csv" "$compare_summary" "$OUT_CSV" <<'PY'
import csv, math, os, re, sys
label,nx,ny,steps,mode,batch,base_summary,run_summary,run_root,compare_csv,compare_summary,out_csv=sys.argv[1:13]
case='tg_periodic_full'
fields=['grid','NX','NY','steps','mode','batchSize','baselineWallTime','modeWallTime','wallDelta_s','wallSpeedup','failed_metrics','compared_metrics','verdict','q6Iterations','q6DivAfterProjectedFluxRms','persistentActiveCalls','totalActiveSeconds','uploadSeconds','kernelSeconds','downloadSeconds','particleStateUploadSeconds','particleStateReusedAllocationFraction','sharedParticleStateFraction','particleStateMetadataCacheHitFraction','sharedCellWorkspaceFraction','cellWorkspaceReusedAllocationFraction','invalidCellParticles','cudaTimingSolves','cudaTimingIterations','cudaTimingBatches','cudaTimingConvergenceDownloads','cudaTimingTotalSeconds','cudaTimingHostReductionSeconds','activeCsv','compareCsv','compareSummary']

def read_one(path, default=None):
    if path == 'none' or not os.path.exists(path):
        if default is not None: return default
        raise SystemExit(f'missing {path}')
    with open(path,newline='') as f: rows=list(csv.DictReader(f))
    if len(rows)!=1: raise SystemExit(f'expected one row in {path}, got {len(rows)}')
    return rows[0]

def f(r,k,default='nan'):
    try: return float(r.get(k,default) or default)
    except Exception: return float('nan')

def i(r,k,default='0'):
    try: return int(round(float(r.get(k,default) or default)))
    except Exception: return 0
base=read_one(base_summary); run=read_one(run_summary)
cmp=read_one(compare_summary, {'failed_metrics':'0','compared_metrics':'0'})
failed=i(cmp,'failed_metrics','0'); compared=i(cmp,'compared_metrics','0')
active_csv=os.path.join(run_root,case,'cuda_persistent_src_collision_thermostat_0215.csv')
rows=[]
if os.path.exists(active_csv):
    with open(active_csv,newline='') as fp: rows=list(csv.DictReader(fp))

def vals(k):
    out=[]
    for r in rows:
        try: out.append(float(r.get(k,'0') or 0.0))
        except Exception: pass
    return out

def sumv(k): return sum(vals(k))
def sum_i(k): return int(round(sumv(k)))
def frac(k):
    if not rows: return 0.0
    return sum(1 for r in rows if str(r.get(k,'0')) not in ('0','0.0','', 'false','False'))/len(rows)
meta_hits=sum_i('particleStateMetadataCacheHits')
invalid=sum_i('invalidCellParticles')
# Parse Q6 timing line when present.
time_path=os.path.join(run_root, f'{case}.time')
kv={}
if os.path.exists(time_path):
    with open(time_path,encoding='utf-8',errors='replace') as fp:
        for line in fp:
            if '[cuda_q6_timing_0192]' in line:
                kv=dict(re.findall(r'([A-Za-z0-9_]+)=([^\s]+)', line))
def tf(k):
    try: return float(kv.get(k,'nan'))
    except Exception: return float('nan')
def ti(k):
    try: return int(round(float(kv.get(k,'0'))))
    except Exception: return 0
wall=f(run,'wallTime'); bwall=f(base,'wallTime')
verdict='PASS' if failed==0 and invalid==0 else 'FAIL'
row={
 'grid':label,'NX':nx,'NY':ny,'steps':steps,'mode':mode,'batchSize':batch if 'q6_cuda' in mode else 0,
 'baselineWallTime':bwall,'modeWallTime':wall,'wallDelta_s':wall-bwall,'wallSpeedup':bwall/wall if wall>0 else float('nan'),
 'failed_metrics':failed,'compared_metrics':compared,'verdict':verdict,
 'q6Iterations':i(run,'q6Iterations'),'q6DivAfterProjectedFluxRms':f(run,'q6DivAfterProjectedFluxRms'),
 'persistentActiveCalls':len(rows),'totalActiveSeconds':sumv('totalSeconds'),'uploadSeconds':sumv('uploadSeconds'),'kernelSeconds':sumv('kernelSeconds'),'downloadSeconds':sumv('downloadSeconds'),
 'particleStateUploadSeconds':sumv('particleStateUploadSeconds'),'particleStateReusedAllocationFraction':frac('particleStateReusedAllocation'),
 'sharedParticleStateFraction':frac('sharedParticleStateEnabled'),'particleStateMetadataCacheHitFraction':meta_hits/len(rows) if rows else 0.0,
 'sharedCellWorkspaceFraction':frac('sharedCellWorkspaceEnabled'),'cellWorkspaceReusedAllocationFraction':frac('cellWorkspaceReusedAllocation'),
 'invalidCellParticles':invalid,'cudaTimingSolves':ti('solves'),'cudaTimingIterations':ti('iterations'),'cudaTimingBatches':ti('deviceScalarCgBatches'),
 'cudaTimingConvergenceDownloads':ti('deviceScalarCgConvergenceDownloads'),'cudaTimingTotalSeconds':tf('totalSeconds'),'cudaTimingHostReductionSeconds':tf('hostReductionSeconds'),
 'activeCsv':active_csv if os.path.exists(active_csv) else 'none','compareCsv':compare_csv,'compareSummary':compare_summary}
with open(out_csv,'a',newline='') as fcsv: csv.DictWriter(fcsv,fieldnames=fields).writerow(row)
print(f"[0226-cell-workspace-q6] {verdict} {label}/{mode}: wall={wall:.6g}s baseline={bwall:.6g}s speedup={row['wallSpeedup']:.4g} sharedP={row['sharedParticleStateFraction']:.2f} sharedC={row['sharedCellWorkspaceFraction']:.2f} q6={row['cudaTimingTotalSeconds']:.3g}s failed={failed}/{compared}")
if verdict!='PASS': raise SystemExit(1)
PY
}

run_mode() {
  local mode=$1 nx=$2 ny=$3 steps=$4 label=$5 baseline_root=$6
  read -r projection persistent shared_particle shared_cell < <(mode_flags "$mode")
  local run_root="runs/cuda_persistent_cell_workspace_q6_0226_${mode}_${label}"
  echo "[0226-cell-workspace-q6] running $label/$mode projection=$projection persistent=$persistent sharedP=$shared_particle sharedC=$shared_cell"
  run_validation "$nx" "$ny" "$steps" "$run_root" "cuda0226_${mode}_${label}" "$projection" "$persistent" "$shared_particle" "$shared_cell"
  local compare_csv="none" compare_summary="none"
  if [[ "$mode" != "cpu_baseline" ]]; then
    compare_csv="$ART_DIR/cuda_persistent_cell_workspace_q6_compare_0226_${mode}_${label}.csv"
    compare_summary="$ART_DIR/cuda_persistent_cell_workspace_q6_compare_summary_0226_${mode}_${label}.csv"
    python3 scripts/compare_validation_mono_config_0162.py \
      --origin "$baseline_root" --optimized "$run_root" \
      --out "$compare_csv" --summary-out "$compare_summary"
  fi
  append_summary "$label" "$nx" "$ny" "$steps" "$mode" "$baseline_root" "$run_root" "$compare_csv" "$compare_summary"
  if [[ "$STOP_ON_FAIL" == "1" && "$mode" != "cpu_baseline" ]]; then
    python3 - "$compare_summary" <<'PY'
import csv, sys, os
p=sys.argv[1]
if p=='none' or not os.path.exists(p): raise SystemExit(1)
with open(p,newline='') as f: r=list(csv.DictReader(f))[0]
raise SystemExit(0 if int(round(float(r.get('failed_metrics','999'))))==0 else 1)
PY
  fi
}

for spec in $GRID_CASES; do
  IFS=: read -r nx steps <<< "$spec"
  [[ -n "${nx:-}" && -n "${steps:-}" ]] || { echo "[0226-cell-workspace-q6] invalid GRID_CASES entry $spec" >&2; exit 2; }
  ny=${NY_OVERRIDE:-$nx}
  label="${nx}x${ny}_s${steps}"
  baseline_root="runs/cuda_persistent_cell_workspace_q6_0226_cpu_baseline_${label}"
  run_mode cpu_baseline "$nx" "$ny" "$steps" "$label" "$baseline_root"
  for mode in $MODES; do
    [[ "$mode" == "cpu_baseline" ]] && continue
    run_mode "$mode" "$nx" "$ny" "$steps" "$label" "$baseline_root"
  done
done

echo "[0226-cell-workspace-q6] wrote $OUT_CSV"
