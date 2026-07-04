#!/usr/bin/env bash
set -euo pipefail
: "${BIN:?Set BIN to the solver binary}"
BASE_PROBE_ROOT="${BASE_PROBE_ROOT:-runs/0461_sparse_gate_probe}"
STEPS="${STEPS:-200}"
SUMMARY_EVERY="${SUMMARY_EVERY:-50}"
DEVICE_GATE_EVERY="${DEVICE_GATE_EVERY:-50}"
RUN_MODES="${RUN_MODES:-src-resampling src-q6-resampling}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-0}"
FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-0}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
MAX_SUMMARY_DELTA_TOL="${MAX_SUMMARY_DELTA_TOL:-1e-9}"
rm -rf "$BASE_PROBE_ROOT"
mkdir -p "$BASE_PROBE_ROOT"
launch_csv="$BASE_PROBE_ROOT/launch_status.csv"
echo "mode,exit_code,elapsed" > "$launch_csv"
for mode in $RUN_MODES; do
  root="$BASE_PROBE_ROOT/sparse_gate/$mode"
  mkdir -p "$root"
  echo "[0461A] mode=$mode root=$root gateEvery=$DEVICE_GATE_EVERY"
  t0=$(python3 - <<'PY'
import time; print(time.time())
PY
)
  set +e
  env \
    BIN="$BIN" \
    BASE_APPLY_ROOT="$root" \
    STEPS="$STEPS" \
    SUMMARY_EVERY="$SUMMARY_EVERY" \
    RUN_MODES="$mode" \
    LIVE_VIS_ENABLE="$LIVE_VIS_ENABLE" \
    FILTERED_RECORDING_ENABLE="$FILTERED_RECORDING_ENABLE" \
    LIVE_PROGRESS="$LIVE_PROGRESS" \
    MAX_SUMMARY_DELTA_TOL="$MAX_SUMMARY_DELTA_TOL" \
    MPCD_CUDA_RESAMPLING_PIPELINE_APPLY_0448=1 \
    MPCD_CUDA_RESAMPLING_UPSTREAM_SHADOW_0450=1 \
    MPCD_CUDA_RESAMPLING_UPSTREAM_APPLY_0451=1 \
    MPCD_CUDA_RESAMPLING_DEVICE_CARRIER_0455=1 \
    MPCD_CUDA_RESAMPLING_THRUST_CELL_LIST_MATERIALIZER_0460=1 \
    MPCD_CUDA_RESAMPLING_CPU_OP_CARRIER_0458=0 \
    MPCD_CUDA_RESAMPLING_DONOR_SLICE_MATERIALIZER_0459=0 \
    MPCD_CUDA_RESAMPLING_SPARSE_DEVICE_CARRIER_GATE_0461=1 \
    MPCD_CUDA_RESAMPLING_DEVICE_CARRIER_GATE_EVERY_0461="$DEVICE_GATE_EVERY" \
    bash scripts/run_0448_periodic_nonzero_plan_apply_smoke.sh
  rc=$?
  set -e
  t1=$(python3 - <<'PY'
import time; print(time.time())
PY
)
  elapsed=$(python3 - <<PY
print(float('$t1')-float('$t0'))
PY
)
  echo "$mode,$rc,$elapsed" >> "$launch_csv"
done
python3 - <<'PY'
import csv, pathlib, os
root=pathlib.Path(os.environ.get('BASE_PROBE_ROOT','runs/0461_sparse_gate_probe'))
tol=float(os.environ.get('MAX_SUMMARY_DELTA_TOL','1e-9'))
keys=['nFluidParticles','totalMass','Px','Py','meanKinetic','kBTEstimate','meanN','stdN']
def rows(p):
    if not p.exists(): return []
    with p.open(newline='') as f: return list(csv.DictReader(f))
def num(r,k):
    try: return float(r.get(k,'0') or 0)
    except Exception: return 0.0
def last(p):
    rs=rows(p); return rs[-1] if rs else {}
launch={}
for r in rows(root/'launch_status.csv'):
    launch[r['mode']]={'rc':int(float(r['exit_code'])),'elapsed':float(r['elapsed'])}
out=[]
for mode,meta in launch.items():
    base=root/'sparse_gate'/mode
    cpu=last(base/'cpu'/mode/'output'/'summary_runtime.csv')
    gpu=last(base/'cuda'/mode/'output'/'summary_runtime.csv')
    deltas={k:abs(num(cpu,k)-num(gpu,k)) for k in keys}
    max_key=max(deltas,key=deltas.get) if deltas else ''
    dev=rows(base/'cuda'/mode/'output'/'cuda_resampling_device_carrier_0455.csv')
    handled=[r for r in dev if int(num(r,'handled'))==1]
    full=[r for r in handled if int(num(r,'fullGate0461'))==1]
    sparse=[r for r in handled if int(num(r,'sparseGate0461'))==1]
    def mx(k): return max([abs(num(r,k)) for r in handled] or [0.0])
    pass_like=(meta['rc']==0 and deltas.get(max_key,0.0)<=tol and len(handled)>0 and len(full)>0 and
               mx('invalidMaterializeOps')==0 and mx('invalidApplyOps')==0 and mx('opMismatch')==0 and mx('duplicateParticleMismatch')==0 and
               mx('thrustCellListMaterializer0460')>0)
    out.append({'mode':mode,'pass':int(pass_like),'smokeExit':meta['rc'],'pairWall':meta['elapsed'],
                'maxSummaryDelta':deltas.get(max_key,0.0),'maxDeltaKey':max_key,'csvRows':len(dev),'handledRows':len(handled),
                'fullGateRows':len(full),'sparseRows':len(sparse),'maxCpuOps':mx('cpuOps'),'maxGpuOps':mx('gpuOps'),
                'invalidMat':mx('invalidMaterializeOps'),'invalidApply':mx('invalidApplyOps'),'opMismatch':mx('opMismatch'),
                'dupMismatch':mx('duplicateParticleMismatch'),'maxMaterializeSeconds':mx('materializeKernelSeconds'),
                'maxGateDownloadSeconds':mx('gateDownloadSeconds'),'maxDeviceTotalSeconds':mx('totalSeconds')})
summary=root/'sparse_gate_summary_0461.csv'
with summary.open('w',newline='') as f:
    w=csv.DictWriter(f,fieldnames=list(out[0].keys()) if out else ['mode']); w.writeheader(); w.writerows(out)
report=root/'sparse_gate_report_0461.md'
with report.open('w') as f:
    f.write('# 0461A sparse device-carrier gate probe\n\n')
    f.write('Scope: periodic nonzero-plan with 0460B Thrust cell-list materializer. This probe keeps CUDA mutation active at every step but only performs the full strict operation-buffer gate every `DEVICE_GATE_EVERY` calls; normal non-full-gate pass rows are omitted from the device-carrier CSV.\n\n')
    f.write(f'PASS-like rows: **{sum(r["pass"] for r in out)}/{len(out)}**\n\n')
    f.write('| mode | pass | smoke exit | pair wall s | max summary delta | max delta key | CSV rows | full-gate rows | sparse rows | ops CPU/GPU | invalid mat/apply | mismatch op/dup | max materialize s | max gate download s | max device total s |\n')
    f.write('| --- | ---: | ---: | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |\n')
    for r in out:
        f.write(f"| {r['mode']} | {r['pass']} | {r['smokeExit']} | {r['pairWall']:.3f} | {r['maxSummaryDelta']:.3e} | {r['maxDeltaKey']} | {r['csvRows']} | {r['fullGateRows']} | {r['sparseRows']} | {r['maxCpuOps']:.0f}/{r['maxGpuOps']:.0f} | {r['invalidMat']:.0f}/{r['invalidApply']:.0f} | {r['opMismatch']:.0f}/{r['dupMismatch']:.0f} | {r['maxMaterializeSeconds']:.3e} | {r['maxGateDownloadSeconds']:.3e} | {r['maxDeviceTotalSeconds']:.3e} |\n")
    f.write(f'\nFlat CSV: `{summary}`\n')
print(report)
PY
