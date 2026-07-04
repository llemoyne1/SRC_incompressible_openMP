#!/usr/bin/env bash
set -euo pipefail

: "${BIN:?Set BIN to the solver binary}"
BASE_SCALE_ROOT="${BASE_SCALE_ROOT:-runs/0463_scaling_cuda_vs_cpu}"
SCALE_CASES="${SCALE_CASES:-64x64x40 96x96x40 128x128x40}"
STEPS="${STEPS:-200}"
SUMMARY_EVERY="${SUMMARY_EVERY:-50}"
DEVICE_GATE_EVERY="${DEVICE_GATE_EVERY:-50}"
SEEDS="${SEEDS:-1628638}"
RUN_MODES="${RUN_MODES:-src-resampling src-q6-resampling}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-0}"
FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-0}"
MAX_SUMMARY_DELTA_TOL="${MAX_SUMMARY_DELTA_TOL:-1e-9}"

if [[ ! -x scripts/run_0462_sparse_gate_stress.sh ]]; then
  echo "[0463] missing scripts/run_0462_sparse_gate_stress.sh" >&2
  exit 2
fi

rm -rf "$BASE_SCALE_ROOT"
mkdir -p "$BASE_SCALE_ROOT"

case_csv="$BASE_SCALE_ROOT/scaling_cases_0463.csv"
echo "case,Nx,Ny,gamma,root" > "$case_csv"

for spec in $SCALE_CASES; do
  IFS='x' read -r NX_CASE NY_CASE GAMMA_CASE <<< "$spec"
  if [[ -z "${NX_CASE:-}" || -z "${NY_CASE:-}" || -z "${GAMMA_CASE:-}" ]]; then
    echo "[0463] bad scale spec '$spec'; expected Nx x Ny x gamma, e.g. 128x128x40" >&2
    exit 2
  fi
  case_name="${NX_CASE}x${NY_CASE}_g${GAMMA_CASE}"
  case_root="$BASE_SCALE_ROOT/$case_name"
  echo "[0463] case=$case_name root=$case_root steps=$STEPS gateEvery=$DEVICE_GATE_EVERY seeds=[$SEEDS] modes=[$RUN_MODES]"
  mkdir -p "$case_root"
  echo "$case_name,$NX_CASE,$NY_CASE,$GAMMA_CASE,$case_root" >> "$case_csv"

  env \
    BIN="$BIN" \
    BASE_STRESS_ROOT="$case_root/stress" \
    STEPS="$STEPS" \
    SUMMARY_EVERY="$SUMMARY_EVERY" \
    DEVICE_GATE_EVERY="$DEVICE_GATE_EVERY" \
    SEEDS="$SEEDS" \
    RUN_MODES="$RUN_MODES" \
    LIVE_PROGRESS="$LIVE_PROGRESS" \
    LIVE_VIS_ENABLE="$LIVE_VIS_ENABLE" \
    FILTERED_RECORDING_ENABLE="$FILTERED_RECORDING_ENABLE" \
    MAX_SUMMARY_DELTA_TOL="$MAX_SUMMARY_DELTA_TOL" \
    NX="$NX_CASE" Nx="$NX_CASE" \
    NY="$NY_CASE" Ny="$NY_CASE" \
    GAMMA="$GAMMA_CASE" gamma="$GAMMA_CASE" \
    bash scripts/run_0462_sparse_gate_stress.sh

done

python3 - <<'PY'
import csv, glob, os, pathlib, math, re

root = pathlib.Path(os.environ.get('BASE_SCALE_ROOT','runs/0463_scaling_cuda_vs_cpu'))
summary_out = root / 'scaling_cuda_vs_cpu_summary_0463.csv'
report_out = root / 'scaling_cuda_vs_cpu_report_0463.md'

def rows(path):
    if not path or not pathlib.Path(path).exists(): return []
    with open(path, newline='') as f: return list(csv.DictReader(f))

def num(row, key, default=0.0):
    try: return float(row.get(key, default) or default)
    except Exception: return default

def last_summary(path):
    rs = rows(path)
    return rs[-1] if rs else {}

def mode_from_path(parts):
    for marker in ('cpu','cuda'):
        if marker in parts:
            i = parts.index(marker)
            if i + 1 < len(parts):
                return parts[i+1]
    return ''

def role_from_path(parts):
    if 'cpu' in parts: return 'cpu'
    if 'cuda' in parts: return 'cuda'
    return ''

case_meta = {}
case_file = root / 'scaling_cases_0463.csv'
for r in rows(case_file):
    case_meta[r['case']] = r

out_rows = []
for case, meta in sorted(case_meta.items()):
    case_root = pathlib.Path(meta['root'])
    stress_summary_files = glob.glob(str(case_root / 'stress' / '**' / 'sparse_gate_stress_summary_0462.csv'), recursive=True)
    stress_rows = []
    for p in stress_summary_files:
        stress_rows += rows(p)

    # Build CPU/CUDA wall map from final summary_runtime.csv files.
    wall = {}
    for p in glob.glob(str(case_root / 'stress' / '**' / 'summary_runtime.csv'), recursive=True):
        pp = pathlib.Path(p)
        parts = list(pp.parts)
        role = role_from_path(parts)
        mode = mode_from_path(parts)
        if not role or not mode: continue
        s = last_summary(p)
        wall[(role, mode)] = max(wall.get((role, mode), 0.0), num(s, 'wallTime'))

    for r in stress_rows:
        mode = r.get('mode','')
        seed = r.get('seed','')
        cpu_wall = wall.get(('cpu', mode), 0.0)
        cuda_wall = wall.get(('cuda', mode), 0.0)
        speedup = (cpu_wall / cuda_wall) if cuda_wall > 0 else 0.0
        out_rows.append({
            'case': case,
            'Nx': meta.get('Nx',''),
            'Ny': meta.get('Ny',''),
            'gamma': meta.get('gamma',''),
            'seed': seed,
            'mode': mode,
            'pass': r.get('pass',''),
            'cpuWall': f'{cpu_wall:.6g}',
            'cudaWall': f'{cuda_wall:.6g}',
            'speedupCpuOverCuda': f'{speedup:.6g}',
            'pairWall': r.get('pairWall',''),
            'maxSummaryDelta': r.get('maxSummaryDelta',''),
            'maxDeltaKey': r.get('maxDeltaKey',''),
            'csvRows': r.get('csvRows',''),
            'fullGateRows': r.get('fullGateRows',''),
            'sparseRows': r.get('sparseRows',''),
            'maxCpuOps': r.get('maxCpuOps',''),
            'maxGpuOps': r.get('maxGpuOps',''),
            'invalidMat': r.get('invalidMat',''),
            'invalidApply': r.get('invalidApply',''),
            'opMismatch': r.get('opMismatch',''),
            'dupMismatch': r.get('dupMismatch',''),
            'maxMaterializeSeconds': r.get('maxMaterializeSeconds',''),
            'maxDeviceTotalSeconds': r.get('maxDeviceTotalSeconds',''),
        })

fields = ['case','Nx','Ny','gamma','seed','mode','pass','cpuWall','cudaWall','speedupCpuOverCuda','pairWall','maxSummaryDelta','maxDeltaKey','csvRows','fullGateRows','sparseRows','maxCpuOps','maxGpuOps','invalidMat','invalidApply','opMismatch','dupMismatch','maxMaterializeSeconds','maxDeviceTotalSeconds']
with open(summary_out, 'w', newline='') as f:
    w = csv.DictWriter(f, fieldnames=fields)
    w.writeheader(); w.writerows(out_rows)

pass_count = sum(1 for r in out_rows if str(r.get('pass','')) == '1')
with open(report_out, 'w') as f:
    f.write('# 0463 CUDA/CPU scaling probe for sparse-gate resampling\n\n')
    f.write('Scope: scaling comparison of CPU baseline versus CUDA sparse-gate path using the 0460 Thrust stable cell-list materializer and the 0461 sparse device-carrier gate. CUDA mutation remains active at every step; full operation-buffer gates are sparse.\n\n')
    f.write(f'Scale cases: `{os.environ.get("SCALE_CASES", "64x64x40 96x96x40 128x128x40")}`\n')
    f.write(f'Seeds: `{os.environ.get("SEEDS", "1628638")}`\n')
    f.write(f'Steps: `{os.environ.get("STEPS", "200")}`, DEVICE_GATE_EVERY: `{os.environ.get("DEVICE_GATE_EVERY", "50")}`\n\n')
    f.write(f'PASS-like rows: **{pass_count}/{len(out_rows)}**\n\n')
    f.write('| case | mode | seed | pass | CPU wall s | CUDA wall s | CPU/CUDA speedup | pair wall s | max summary delta | CSV/full/sparse rows | ops CPU/GPU | invalid mat/apply | mismatch op/dup | max materialize s | max device total s |\n')
    f.write('| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |\n')
    for r in out_rows:
        f.write(f"| {r['case']} | {r['mode']} | {r['seed']} | {r['pass']} | {float(r['cpuWall'] or 0):.3f} | {float(r['cudaWall'] or 0):.3f} | {float(r['speedupCpuOverCuda'] or 0):.3f} | {float(r['pairWall'] or 0):.3f} | {float(r['maxSummaryDelta'] or 0):.3e} | {r['csvRows']}/{r['fullGateRows']}/{r['sparseRows']} | {float(r['maxCpuOps'] or 0):.0f}/{float(r['maxGpuOps'] or 0):.0f} | {float(r['invalidMat'] or 0):.0f}/{float(r['invalidApply'] or 0):.0f} | {float(r['opMismatch'] or 0):.0f}/{float(r['dupMismatch'] or 0):.0f} | {float(r['maxMaterializeSeconds'] or 0):.3e} | {float(r['maxDeviceTotalSeconds'] or 0):.3e} |\n")
    f.write(f'\nFlat CSV: `{summary_out}`\n')
print(report_out)
PY
