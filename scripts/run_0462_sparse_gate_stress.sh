#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

: "${BIN:?Set BIN to the solver binary}"
BASE_STRESS_ROOT="${BASE_STRESS_ROOT:-runs/0462_sparse_gate_stress}"
STEPS="${STEPS:-200}"
SUMMARY_EVERY="${SUMMARY_EVERY:-50}"
DEVICE_GATE_EVERY="${DEVICE_GATE_EVERY:-50}"
RUN_MODES="${RUN_MODES:-src-resampling src-q6-resampling}"
SEEDS="${SEEDS:-1628638 1628639 1628640}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-0}"
FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-0}"
MAX_SUMMARY_DELTA_TOL="${MAX_SUMMARY_DELTA_TOL:-1e-9}"

if [[ ! -x scripts/run_0461_sparse_gate_probe.sh ]]; then
  echo "[0462] missing scripts/run_0461_sparse_gate_probe.sh" >&2
  exit 2
fi

rm -rf "$BASE_STRESS_ROOT"
mkdir -p "$BASE_STRESS_ROOT"
launch_csv="$BASE_STRESS_ROOT/launch_status.csv"
echo "seed,exit_code,elapsed,root" > "$launch_csv"

for seed in $SEEDS; do
  root="$BASE_STRESS_ROOT/seed_${seed}"
  echo "[0462] seed=$seed root=$root"
  t0=$(python3 - <<'PY'
import time
print(time.time())
PY
)
  set +e
  BIN="$BIN" \
  BASE_PROBE_ROOT="$root" \
  STEPS="$STEPS" \
  SUMMARY_EVERY="$SUMMARY_EVERY" \
  DEVICE_GATE_EVERY="$DEVICE_GATE_EVERY" \
  SEED="$seed" \
  RUN_MODES="$RUN_MODES" \
  LIVE_PROGRESS="$LIVE_PROGRESS" \
  LIVE_VIS_ENABLE="$LIVE_VIS_ENABLE" \
  FILTERED_RECORDING_ENABLE="$FILTERED_RECORDING_ENABLE" \
  MAX_SUMMARY_DELTA_TOL="$MAX_SUMMARY_DELTA_TOL" \
  bash scripts/run_0461_sparse_gate_probe.sh
  ec=$?
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
  echo "$seed,$ec,$elapsed,$root" >> "$launch_csv"
done

python3 - <<'PY'
import csv, os, pathlib, math
root=pathlib.Path(os.environ.get('BASE_STRESS_ROOT','runs/0462_sparse_gate_stress'))
tol=float(os.environ.get('MAX_SUMMARY_DELTA_TOL','1e-9'))
summary_out=root/'sparse_gate_stress_summary_0462.csv'
report=root/'sparse_gate_stress_report_0462.md'

launch=[]
with (root/'launch_status.csv').open(newline='') as f:
    launch=list(csv.DictReader(f))

rows=[]
for l in launch:
    seed=l['seed']; seed_root=pathlib.Path(l['root'])
    p=seed_root/'sparse_gate_summary_0461.csv'
    if not p.exists():
        rows.append({'seed':seed,'mode':'<missing>','pass':0,'reason':'missing sparse_gate_summary_0461.csv','smokeExit':l.get('exit_code','')})
        continue
    with p.open(newline='') as f:
        for r in csv.DictReader(f):
            out={'seed':seed,'reason':''}
            out.update(r)
            rows.append(out)

field_order=['seed','mode','pass','smokeExit','pairWall','maxSummaryDelta','maxDeltaKey','csvRows','fullGateRows','sparseRows','maxCpuOps','maxGpuOps','invalidMat','invalidApply','opMismatch','dupMismatch','maxMaterializeSeconds','maxGateDownloadSeconds','maxDeviceTotalSeconds','reason']
fields=[]
for f in field_order:
    if any(f in r for r in rows): fields.append(f)
for r in rows:
    for k in r:
        if k not in fields: fields.append(k)
with summary_out.open('w',newline='') as f:
    w=csv.DictWriter(f,fieldnames=fields)
    w.writeheader(); w.writerows(rows)

def num(r,k,default=0.0):
    try: return float(r.get(k,'') or default)
    except Exception: return default

def is_pass(r):
    return int(num(r,'pass',0))==1 and int(num(r,'smokeExit',0))==0 and num(r,'maxSummaryDelta',1.0) <= tol and num(r,'invalidMat',1.0)==0 and num(r,'invalidApply',1.0)==0 and num(r,'opMismatch',1.0)==0 and num(r,'dupMismatch',1.0)==0 and num(r,'fullGateRows',0)>0 and num(r,'csvRows',0)==num(r,'fullGateRows',-1)

valid=[r for r in rows if r.get('mode') not in ('<missing>',None)]
pass_count=sum(1 for r in valid if is_pass(r))

with report.open('w') as f:
    f.write('# 0462 sparse-gate stress validation\n\n')
    f.write('Scope: multi-seed periodic nonzero-plan validation of the 0461 sparse gate on top of the 0460 Thrust stable cell-list materializer. CUDA mutation remains active every step; full operation-buffer gates and device-carrier CSV rows are sparse.\n\n')
    f.write(f'Seeds: `{os.environ.get("SEEDS","1628638 1628639 1628640")}`  \n')
    f.write(f'Steps: `{os.environ.get("STEPS","200")}`, DEVICE_GATE_EVERY: `{os.environ.get("DEVICE_GATE_EVERY","50")}`  \n\n')
    f.write(f'PASS-like rows: **{pass_count}/{len(valid)}**\n\n')
    f.write('| seed | mode | pass | smoke exit | pair wall s | max summary delta | max delta key | CSV rows | full gate rows | sparse rows | ops CPU/GPU | invalid mat/apply | mismatch op/dup | max materialize s | max gate download s | max device total s |\n')
    f.write('| ---: | --- | ---: | ---: | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |\n')
    for r in valid:
        f.write(f"| {r.get('seed','')} | {r.get('mode','')} | {1 if is_pass(r) else 0} | {int(num(r,'smokeExit',0))} | {num(r,'pairWall'):.3f} | {num(r,'maxSummaryDelta'):.3e} | {r.get('maxDeltaKey','')} | {num(r,'csvRows'):.0f} | {num(r,'fullGateRows'):.0f} | {num(r,'sparseRows'):.0f} | {num(r,'maxCpuOps'):.0f}/{num(r,'maxGpuOps'):.0f} | {num(r,'invalidMat'):.0f}/{num(r,'invalidApply'):.0f} | {num(r,'opMismatch'):.0f}/{num(r,'dupMismatch'):.0f} | {num(r,'maxMaterializeSeconds'):.3e} | {num(r,'maxGateDownloadSeconds'):.3e} | {num(r,'maxDeviceTotalSeconds'):.3e} |\n")
    missing=[r for r in rows if r.get('mode')=='<missing>']
    if missing:
        f.write('\nMissing/failed seed summaries:\n')
        for r in missing:
            f.write(f"- seed {r.get('seed')}: {r.get('reason')}\n")
    f.write(f'\nFlat CSV: `{summary_out}`\n')
print(report)
PY
