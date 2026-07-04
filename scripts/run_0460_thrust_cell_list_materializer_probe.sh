#!/usr/bin/env bash
set -euo pipefail

: "${BIN:?Set BIN to the solver binary}"
BASE_PROBE_ROOT="${BASE_PROBE_ROOT:-runs/0460_thrust_cell_list_materializer_probe}"
STEPS="${STEPS:-200}"
SUMMARY_EVERY="${SUMMARY_EVERY:-50}"
RUN_MODES="${RUN_MODES:-src-resampling src-q6-resampling}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-0}"
FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-0}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
MAX_SUMMARY_DELTA_TOL="${MAX_SUMMARY_DELTA_TOL:-1e-9}"

rm -rf "$BASE_PROBE_ROOT"
mkdir -p "$BASE_PROBE_ROOT"

launch_csv="$BASE_PROBE_ROOT/launch_status.csv"
echo "mode,smoke_exit,pair_elapsed" > "$launch_csv"

for mode in $RUN_MODES; do
  root="$BASE_PROBE_ROOT/thrust_cell_list/$mode"
  mkdir -p "$root"
  echo "[0460B] mode=$mode root=$root"
  t0=$(python3 - <<'PY'
import time
print(time.time())
PY
)
  set +e
  env \
    BIN="$BIN" \
    BASE_DEVICE_CARRIER_ROOT="$root" \
    STEPS="$STEPS" \
    SUMMARY_EVERY="$SUMMARY_EVERY" \
    RUN_MODES="$mode" \
    LIVE_PROGRESS="$LIVE_PROGRESS" \
    LIVE_VIS_ENABLE="$LIVE_VIS_ENABLE" \
    FILTERED_RECORDING_ENABLE="$FILTERED_RECORDING_ENABLE" \
    MAX_SUMMARY_DELTA_TOL="$MAX_SUMMARY_DELTA_TOL" \
    MPCD_CUDA_RESAMPLING_PIPELINE_APPLY_0448=1 \
    MPCD_CUDA_RESAMPLING_UPSTREAM_SHADOW_0450=1 \
    MPCD_CUDA_RESAMPLING_UPSTREAM_APPLY_0451=1 \
    MPCD_CUDA_RESAMPLING_OPERATION_MATERIALIZE_0453=0 \
    MPCD_CUDA_RESAMPLING_DEVICE_CARRIER_0455=1 \
    MPCD_CUDA_RESAMPLING_CPU_OP_CARRIER_0458=0 \
    MPCD_CUDA_RESAMPLING_DONOR_SLICE_MATERIALIZER_0459=0 \
    MPCD_CUDA_RESAMPLING_THRUST_CELL_LIST_MATERIALIZER_0460=1 \
    bash scripts/run_0455_device_carrier_smoke.sh
  rc=$?
  set -e
  t1=$(python3 - <<'PY'
import time
print(time.time())
PY
)
  elapsed=$(python3 - <<PY
print(float('$t1')-float('$t0'))
PY
)
  echo "$mode,$rc,$elapsed" >> "$launch_csv"
done

python3 - <<'PY'
import csv, os, pathlib
root=pathlib.Path(os.environ.get('BASE_PROBE_ROOT','runs/0460_thrust_cell_list_materializer_probe'))
tol=float(os.environ.get('MAX_SUMMARY_DELTA_TOL','1e-9'))
keys=['nFluidParticles','totalMass','Px','Py','meanKinetic','kBTEstimate','meanN','stdN']

def rows(path):
    p=pathlib.Path(path)
    if not p.exists(): return []
    with p.open(newline='') as f: return list(csv.DictReader(f))

def last(path):
    rs=rows(path); return rs[-1] if rs else {}

def num(r,k):
    try: return float(r.get(k,'0') or 0)
    except Exception: return 0.0

def mx(rs,k): return max([abs(num(r,k)) for r in rs] or [0.0])

out=[]
for l in rows(root/'launch_status.csv'):
    mode=l['mode']
    base=root/'thrust_cell_list'/mode
    cpu_paths=list(base.glob('cpu/*/output/summary_runtime.csv'))
    gpu_paths=list(base.glob('cuda/*/output/summary_runtime.csv'))
    cpu=last(cpu_paths[0]) if cpu_paths else {}
    gpu=last(gpu_paths[0]) if gpu_paths else {}
    deltas={k:abs(num(cpu,k)-num(gpu,k)) for k in keys}
    max_key=max(deltas, key=deltas.get) if deltas else ''
    max_delta=deltas.get(max_key,0.0)
    dev=[]
    for p in base.glob('cuda/*/output/cuda_resampling_device_carrier_0455.csv'):
        dev += rows(p)
    handled=[r for r in dev if int(num(r,'handled'))==1]
    thrust_rows=sum(1 for r in handled if num(r,'thrustCellListMaterializer0460')>0)
    pass_like=(max_delta<=tol and len(handled)>0 and thrust_rows>0 and mx(handled,'invalidMaterializeOps')==0 and mx(handled,'invalidApplyOps')==0 and mx(handled,'opMismatch')==0 and mx(handled,'duplicateParticleMismatch')==0 and mx(handled,'cpuOps')==mx(handled,'gpuOps') and mx(handled,'cpuOps')>0)
    out.append({
        'mode':mode,
        'pass':int(pass_like),
        'smokeExit':int(float(l.get('smoke_exit',1))),
        'pairWall':float(l.get('pair_elapsed',0.0)),
        'maxSummaryDelta':max_delta,
        'maxDeltaKey':max_key,
        'deviceRows':len(dev),
        'thrustCellListRows':thrust_rows,
        'maxCpuOps':mx(handled,'cpuOps'),
        'maxGpuOps':mx(handled,'gpuOps'),
        'invalidMat':mx(handled,'invalidMaterializeOps'),
        'invalidApply':mx(handled,'invalidApplyOps'),
        'opMismatch':mx(handled,'opMismatch'),
        'dupMismatch':mx(handled,'duplicateParticleMismatch'),
        'maxMaterializeSeconds':mx(handled,'materializeKernelSeconds'),
        'maxDeviceTotalSeconds':mx(handled,'totalSeconds'),
    })

summary=root/'thrust_cell_list_materializer_summary_0460.csv'
with summary.open('w',newline='') as f:
    fields=list(out[0].keys()) if out else ['mode']
    w=csv.DictWriter(f,fieldnames=fields); w.writeheader(); w.writerows(out)

report=root/'thrust_cell_list_materializer_report_0460.md'
with report.open('w') as f:
    f.write('# 0460B Thrust stable cell-list CUDA materializer probe\n\n')
    f.write('Scope: periodic nonzero-plan. This probe enables `MPCD_CUDA_RESAMPLING_THRUST_CELL_LIST_MATERIALIZER_0460=1`, disables the 0458 CPU-op carrier and the 0459 host-built donor-slice materializer, builds a stable GPU cell list by sorting `(cellId, particleIndex)`, and materializes donor operations from exact cell slices. The donor-cell set still comes from the accepted transfer plan.\n\n')
    f.write(f'PASS-like rows: **{sum(r["pass"] for r in out)}/{len(out)}**\n\n')
    f.write('| mode | pass | smoke exit | pair wall s | max summary delta | max delta key | device rows | thrust-cell-list rows | ops CPU/GPU | invalid mat/apply | mismatch op/dup | max materialize s | max device total s |\n')
    f.write('| --- | ---: | ---: | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |\n')
    for r in out:
        f.write(f"| {r['mode']} | {r['pass']} | {r['smokeExit']} | {r['pairWall']:.3f} | {r['maxSummaryDelta']:.3e} | {r['maxDeltaKey']} | {r['deviceRows']} | {r['thrustCellListRows']} | {r['maxCpuOps']:.0f}/{r['maxGpuOps']:.0f} | {r['invalidMat']:.0f}/{r['invalidApply']:.0f} | {r['opMismatch']:.0f}/{r['dupMismatch']:.0f} | {r['maxMaterializeSeconds']:.3e} | {r['maxDeviceTotalSeconds']:.3e} |\n")
    f.write(f'\nFlat CSV: `{summary}`\n')
print(report)
PY
