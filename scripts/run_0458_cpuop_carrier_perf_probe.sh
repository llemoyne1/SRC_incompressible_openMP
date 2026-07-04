#!/usr/bin/env bash
set -uo pipefail

: "${BIN:?Set BIN to the solver binary}"
BASE_PROBE_ROOT="${BASE_PROBE_ROOT:-runs/0458_cpuop_carrier_perf_probe}"
STEPS="${STEPS:-200}"
SUMMARY_EVERY="${SUMMARY_EVERY:-50}"
RUN_MODES="${RUN_MODES:-src-resampling src-q6-resampling}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-0}"
FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-0}"
MAX_SUMMARY_DELTA_TOL="${MAX_SUMMARY_DELTA_TOL:-1e-9}"

rm -rf "$BASE_PROBE_ROOT"
mkdir -p "$BASE_PROBE_ROOT"

if [[ ! -x scripts/run_0455_device_carrier_smoke.sh ]]; then
  echo "[0458B] missing scripts/run_0455_device_carrier_smoke.sh" >&2
  exit 2
fi

launch_csv="$BASE_PROBE_ROOT/launch_status.csv"
echo "mode,elapsed,smoke_exit" > "$launch_csv"

for mode in $RUN_MODES; do
  root="$BASE_PROBE_ROOT/cuda_cpuop/$mode"
  mkdir -p "$root"
  echo "[0458B] mode=$mode root=$root"
  t0=$(python3 - <<'PY'
import time
print(time.time())
PY
)

  if [[ "$LIVE_PROGRESS" == "1" ]]; then
    env \
      BIN="$BIN" \
      BASE_DEVICE_CARRIER_ROOT="$root" \
      STEPS="$STEPS" \
      SUMMARY_EVERY="$SUMMARY_EVERY" \
      RUN_MODES="$mode" \
      LIVE_PROGRESS="$LIVE_PROGRESS" \
      LIVE_VIS_ENABLE="$LIVE_VIS_ENABLE" \
      FILTERED_RECORDING_ENABLE="$FILTERED_RECORDING_ENABLE" \
      MPCD_CUDA_RESAMPLING_PIPELINE_APPLY_0448=1 \
      MPCD_CUDA_RESAMPLING_UPSTREAM_SHADOW_0450=1 \
      MPCD_CUDA_RESAMPLING_UPSTREAM_APPLY_0451=1 \
      MPCD_CUDA_RESAMPLING_OPERATION_MATERIALIZE_0453=0 \
      MPCD_CUDA_RESAMPLING_DEVICE_CARRIER_0455=1 \
      MPCD_CUDA_RESAMPLING_CPU_OP_CARRIER_0458=1 \
      bash scripts/run_0455_device_carrier_smoke.sh
    smoke_exit=$?
  else
    env \
      BIN="$BIN" \
      BASE_DEVICE_CARRIER_ROOT="$root" \
      STEPS="$STEPS" \
      SUMMARY_EVERY="$SUMMARY_EVERY" \
      RUN_MODES="$mode" \
      LIVE_PROGRESS="$LIVE_PROGRESS" \
      LIVE_VIS_ENABLE="$LIVE_VIS_ENABLE" \
      FILTERED_RECORDING_ENABLE="$FILTERED_RECORDING_ENABLE" \
      MPCD_CUDA_RESAMPLING_PIPELINE_APPLY_0448=1 \
      MPCD_CUDA_RESAMPLING_UPSTREAM_SHADOW_0450=1 \
      MPCD_CUDA_RESAMPLING_UPSTREAM_APPLY_0451=1 \
      MPCD_CUDA_RESAMPLING_OPERATION_MATERIALIZE_0453=0 \
      MPCD_CUDA_RESAMPLING_DEVICE_CARRIER_0455=1 \
      MPCD_CUDA_RESAMPLING_CPU_OP_CARRIER_0458=1 \
      bash scripts/run_0455_device_carrier_smoke.sh > "$root/wrapper_0458b.log" 2>&1
    smoke_exit=$?
  fi

  t1=$(python3 - <<'PY'
import time
print(time.time())
PY
)
  elapsed=$(python3 - <<PY
print(float('$t1')-float('$t0'))
PY
)
  echo "$mode,$elapsed,$smoke_exit" >> "$launch_csv"
  if [[ "$smoke_exit" != "0" ]]; then
    echo "[0458B] warning: smoke script returned $smoke_exit for mode=$mode; continuing to aggregate available CSVs" >&2
  fi
done

python3 - <<'PY'
import csv, glob, os, pathlib
root = pathlib.Path(os.environ.get('BASE_PROBE_ROOT','runs/0458_cpuop_carrier_perf_probe'))
tol = float(os.environ.get('MAX_SUMMARY_DELTA_TOL','1e-9'))
run_modes = os.environ.get('RUN_MODES','src-resampling src-q6-resampling').split()
keys = ['nFluidParticles','nInactiveParticles','totalMass','Px','Py','meanKinetic','kBTEstimate','meanParticleSpeed','maxParticleSpeed','resampMeanN','resampStdN','resampParticleMassStd','resampMeanUx','resampMeanUy','resampCellUxRms','resampCellUyRms']

def read_last(path):
    with open(path, newline='') as f:
        rows = list(csv.DictReader(f))
    return rows[-1] if rows else {}

def num(row, k):
    try:
        return float(row.get(k, '0') or 0)
    except Exception:
        return 0.0

def read_csv_rows(path):
    with open(path, newline='') as f:
        return list(csv.DictReader(f))

def first_existing(patterns):
    for pat in patterns:
        hits = sorted(glob.glob(str(pat), recursive=True))
        if hits:
            return pathlib.Path(hits[0])
    return None

launch = {}
launch_path = root / 'launch_status.csv'
if launch_path.exists():
    with open(launch_path, newline='') as f:
        for r in csv.DictReader(f):
            launch[r.get('mode','')] = {'elapsed': float(r.get('elapsed','0') or 0), 'smoke_exit': int(float(r.get('smoke_exit','999') or 999))}

rows = []
errors = []
for mode in run_modes:
    mode_root = root / 'cuda_cpuop' / mode
    cpu_path = first_existing([mode_root / 'cpu' / mode / 'output' / 'summary_runtime.csv', mode_root / 'cpu' / '*' / 'output' / 'summary_runtime.csv'])
    cu_path = first_existing([mode_root / 'cuda' / mode / 'output' / 'summary_runtime.csv', mode_root / 'cuda' / '*' / 'output' / 'summary_runtime.csv'])
    dev_files = sorted(glob.glob(str(mode_root / 'cuda' / '**' / 'cuda_resampling_device_carrier_0455.csv'), recursive=True))
    if cpu_path is None or cu_path is None:
        rows.append({'mode': mode, 'pass': 0, 'smokeExit': launch.get(mode,{}).get('smoke_exit',999), 'pairWall': launch.get(mode,{}).get('elapsed',0.0), 'cpuWall': 0.0, 'cudaWall': 0.0, 'maxSummaryDelta': float('inf'), 'maxDeltaKey': 'missing_summary', 'deviceRows': 0, 'cpuOpCarrierRows': 0, 'maxCpuOps': 0, 'maxGpuOps': 0, 'invalidMat': 0, 'invalidApply': 0, 'opMismatch': 0, 'dupMismatch': 0, 'maxMaterializeSeconds': 0, 'maxDeviceTotalSeconds': 0, 'cpuPath': str(cpu_path or ''), 'cudaPath': str(cu_path or ''), 'deviceCsv': ';'.join(dev_files)})
        continue
    cpu = read_last(cpu_path); cu = read_last(cu_path)
    deltas = {k: abs(num(cpu,k)-num(cu,k)) for k in keys}
    max_key = max(deltas, key=deltas.get) if deltas else 'none'
    max_delta = deltas.get(max_key, 0.0)
    dev_rows = []
    for p in dev_files:
        try:
            dev_rows.extend(read_csv_rows(p))
        except Exception as exc:
            errors.append(f'{p}: {exc}')
    def mx(k): return max([abs(num(r,k)) for r in dev_rows] or [0.0])
    pass_like = (max_delta <= tol and mx('invalidMaterializeOps') == 0 and mx('invalidApplyOps') == 0 and mx('opMismatch') == 0 and mx('duplicateParticleMismatch') == 0 and sum(1 for r in dev_rows if num(r,'cpuOpCarrier0458') > 0) > 0)
    rows.append({'mode': mode, 'pass': int(pass_like), 'smokeExit': launch.get(mode,{}).get('smoke_exit',999), 'pairWall': launch.get(mode,{}).get('elapsed',0.0), 'cpuWall': num(cpu,'wallTime'), 'cudaWall': num(cu,'wallTime'), 'maxSummaryDelta': max_delta, 'maxDeltaKey': max_key, 'deviceRows': len(dev_rows), 'cpuOpCarrierRows': sum(1 for r in dev_rows if num(r,'cpuOpCarrier0458') > 0), 'maxCpuOps': mx('cpuOps'), 'maxGpuOps': mx('gpuOps'), 'invalidMat': mx('invalidMaterializeOps'), 'invalidApply': mx('invalidApplyOps'), 'opMismatch': mx('opMismatch'), 'dupMismatch': mx('duplicateParticleMismatch'), 'maxMaterializeSeconds': mx('materializeKernelSeconds'), 'maxDeviceTotalSeconds': mx('totalSeconds'), 'cpuPath': str(cpu_path), 'cudaPath': str(cu_path), 'deviceCsv': ';'.join(dev_files)})

summary = root / 'cpuop_carrier_perf_summary_0458.csv'
fieldnames = list(rows[0].keys()) if rows else ['mode']
with open(summary, 'w', newline='') as f:
    w = csv.DictWriter(f, fieldnames=fieldnames); w.writeheader(); w.writerows(rows)
report = root / 'cpuop_carrier_perf_report_0458.md'
with open(report, 'w') as f:
    f.write('# 0458B CPU-op carrier performance bridge\n\n')
    f.write('Scope: periodic nonzero-plan. This diagnostic bypasses the serial CUDA donor-particle materializer by uploading the accepted CPU passive operation vector into device-carrier buffers. It is not the final host-free materializer; it isolates the remaining CUDA apply/remap/thermal path.\n\n')
    f.write(f'PASS-like rows: **{sum(r["pass"] for r in rows)}/{len(rows)}**\n\n')
    f.write('| mode | pass | smoke exit | pair wall s | cpu wall s | cuda cpu-op wall s | max summary delta | max delta key | device rows | cpuOpCarrier rows | ops CPU/GPU | invalid mat/apply | mismatch op/dup | max materialize s | max device total s |\n')
    f.write('| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |\n')
    for r in rows:
        f.write(f"| {r['mode']} | {r['pass']} | {r['smokeExit']} | {r['pairWall']:.3f} | {r['cpuWall']:.3f} | {r['cudaWall']:.3f} | {r['maxSummaryDelta']:.3e} | {r['maxDeltaKey']} | {r['deviceRows']} | {r['cpuOpCarrierRows']} | {r['maxCpuOps']:.0f}/{r['maxGpuOps']:.0f} | {r['invalidMat']:.0f}/{r['invalidApply']:.0f} | {r['opMismatch']:.0f}/{r['dupMismatch']:.0f} | {r['maxMaterializeSeconds']:.3e} | {r['maxDeviceTotalSeconds']:.3e} |\n")
    f.write(f'\nFlat CSV: `{summary}`\n')
    if errors:
        f.write('\nAggregation warnings:\n')
        for e in errors:
            f.write(f'- {e}\n')
print(report)
PY
