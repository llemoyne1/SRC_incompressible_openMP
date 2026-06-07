#!/usr/bin/env bash
set -euo pipefail

# 0281 — consolidated validation for the CUDA thermostat work package.
#
# This script intentionally does not enable Q6 CUDA. It consolidates the already
# validated physical thermostat paths:
#   wall-simple          : fused CUDA SRC+thermostat, real-particle thermostat moments
#   solid/rectangle      : fused CUDA SRC+thermostat, real-particle thermostat moments
#   piston/mobile wall   : CUDA SRC -> CPU Q6/resampling/virial/capacity -> CUDA post-CPU thermostat
#   inlet/outlet fullface: resident CUDA IO -> fused CUDA SRC+thermostat
#   inlet/outlet segment : resident CUDA segmented IO -> fused CUDA SRC+thermostat
#
# Default grid set is the discriminant two-size run used to validate 0276-0280c.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BIN=${BIN:-build/src_mpcd_base_cuda_0281}
ART_DIR=${ART_DIR:-dev_history/artifacts/gpu_cuda_persistent_src_thermostat_consolidated_0281}
GRID_CASES=${GRID_CASES:-"64:64:300 128:128:300"}
FORCE_REBUILD=${FORCE_REBUILD:-1}
STOP_ON_FAIL=${STOP_ON_FAIL:-1}

RUN_WALL=${RUN_WALL:-1}
RUN_SOLID=${RUN_SOLID:-1}
RUN_PISTON=${RUN_PISTON:-1}
RUN_IO_FULLFACE=${RUN_IO_FULLFACE:-1}
RUN_IO_SEGMENTED=${RUN_IO_SEGMENTED:-1}

mkdir -p "$ART_DIR"

need_script() {
  local f=$1
  if [[ ! -f "$f" ]]; then
    echo "[0281-consolidated] ERROR: missing required script $f" >&2
    echo "[0281-consolidated] Apply patches 0276, 0277, 0278, 0280c before running 0281." >&2
    exit 2
  fi
}

if [[ "$FORCE_REBUILD" != "0" && "$FORCE_REBUILD" != "false" && "$FORCE_REBUILD" != "FALSE" ]]; then
  echo "[0281-consolidated] rebuilding $BIN"
  OUT="$BIN" CUDA_ARCH_FLAGS=${CUDA_ARCH_FLAGS:-} bash scripts/build_src_mpcd_cuda_0281.sh
elif [[ ! -x "$BIN" ]]; then
  OUT="$BIN" CUDA_ARCH_FLAGS=${CUDA_ARCH_FLAGS:-} bash scripts/build_src_mpcd_cuda_0281.sh
fi
if [[ ! -x "$BIN" ]]; then
  echo "[0281-consolidated] ERROR: missing binary $BIN" >&2
  exit 127
fi

run_one() {
  local label=$1 script=$2 subdir=$3 csv_name=$4
  need_script "$script"
  echo "[0281-consolidated] running $label GRID_CASES=[$GRID_CASES]"
  BIN="$BIN" GRID_CASES="$GRID_CASES" FORCE_REBUILD=0 STOP_ON_FAIL="$STOP_ON_FAIL" \
    ART_DIR="$ART_DIR/$subdir" bash "$script"
  echo "$label,$ART_DIR/$subdir/$csv_name" >> "$ART_DIR/.csv_inputs.tmp"
}

: > "$ART_DIR/.csv_inputs.tmp"

if [[ "$RUN_WALL" != "0" ]]; then
  run_one wall_0276 scripts/run_cuda_persistent_src_thermostat_wall_0276.sh wall_0276 cuda_persistent_src_thermostat_wall_0276.csv
fi
if [[ "$RUN_SOLID" != "0" ]]; then
  run_one solid_0277 scripts/run_cuda_persistent_src_thermostat_solid_0277.sh solid_0277 cuda_persistent_src_thermostat_solid_0277.csv
fi
if [[ "$RUN_PISTON" != "0" ]]; then
  run_one piston_0278 scripts/run_cuda_persistent_src_thermostat_piston_0278.sh piston_0278 cuda_persistent_src_thermostat_piston_0278.csv
fi
if [[ "$RUN_IO_FULLFACE" != "0" ]]; then
  run_one io_fullface_0279b scripts/run_cuda_persistent_src_thermostat_io_fullface_0279b.sh io_fullface_0279b cuda_persistent_src_thermostat_io_fullface_0279b.csv
fi
if [[ "$RUN_IO_SEGMENTED" != "0" ]]; then
  run_one io_segmented_0280c scripts/run_cuda_persistent_src_thermostat_io_segmented_0280c.sh io_segmented_0280c cuda_persistent_src_thermostat_io_segmented_0280c.csv
fi

OUT_CSV=${OUT_CSV:-$ART_DIR/cuda_persistent_src_thermostat_consolidated_0281.csv}
OUT_SUMMARY=${OUT_SUMMARY:-$ART_DIR/cuda_persistent_src_thermostat_consolidated_0281_summary.txt}

python3 - "$ART_DIR/.csv_inputs.tmp" "$OUT_CSV" "$OUT_SUMMARY" <<'PY'
import csv, math, os, sys
inputs_path, out_csv, out_summary = sys.argv[1:4]

def as_float(v, default=math.nan):
    try:
        if v is None or v == '':
            return default
        return float(v)
    except Exception:
        return default

def as_int(v, default=0):
    try:
        if v is None or v == '':
            return default
        return int(float(v))
    except Exception:
        return default

inputs=[]
with open(inputs_path, newline='') as fh:
    for line in fh:
        line=line.strip()
        if not line:
            continue
        label, path = line.split(',', 1)
        inputs.append((label, path))

rows_out=[]
errors=[]
for label, path in inputs:
    if not os.path.exists(path):
        errors.append(f'{label}: missing csv {path}')
        continue
    with open(path, newline='') as fh:
        rows=list(csv.DictReader(fh))
    real_rows=[]
    for r in rows:
        # Older 0276 runners may contain a stray one-column compareSummary row.
        # Keep only rows that actually have a verdict and grid.
        if not r.get('verdict') or not r.get('grid'):
            continue
        real_rows.append(r)
    if not real_rows:
        errors.append(f'{label}: no usable result rows in {path}')
        continue
    for r in real_rows:
        verdict=(r.get('verdict') or '').strip()
        failed=as_int(r.get('failed_metrics'), 999999)
        compared=as_int(r.get('compared_metrics'), 0)
        thermo_gpu=as_float(r.get('thermostatGpuAppliedFraction', r.get('collisionThermostatAppliedOnGpuFraction', 'nan')))
        post_cpu=as_int(r.get('postCpuThermostatPersistent0258'), 0)
        fused=as_int(r.get('fusedSrcThermostatUse'), 0)
        thermo_calls=as_int(r.get('thermostatActiveCalls'), 0)
        kbt_after=as_float(r.get('thermostatKBTAfterMean'))
        speedup=as_float(r.get('totalWallSpeedup'))
        checks=[]
        ok = verdict == 'PASS' and failed == 0 and compared > 0
        checks.append('compare=PASS' if ok else 'compare=FAIL')
        if label == 'piston_0278':
            ok = ok and fused == 0 and post_cpu == 1 and thermo_calls > 0
            checks.append('post_cpu_thermostat=OK' if fused == 0 and post_cpu == 1 and thermo_calls > 0 else 'post_cpu_thermostat=FAIL')
        else:
            ok = ok and (math.isfinite(thermo_gpu) and abs(thermo_gpu - 1.0) < 1e-12)
            checks.append('fused_gpu_thermostat=OK' if math.isfinite(thermo_gpu) and abs(thermo_gpu - 1.0) < 1e-12 else 'fused_gpu_thermostat=FAIL')
        if label == 'io_fullface_0279b':
            ok = ok and as_int(r.get('ioFullfaceResidentFlag'), 0) == 1 and fused == 1 and post_cpu == 0
            checks.append('fullface_resident=OK' if as_int(r.get('ioFullfaceResidentFlag'), 0) == 1 and fused == 1 and post_cpu == 0 else 'fullface_resident=FAIL')
        if label == 'io_segmented_0280c':
            ok = ok and as_int(r.get('ioSegmentedResidentFlag'), 0) == 1 and fused == 1 and post_cpu == 0
            checks.append('segmented_resident=OK' if as_int(r.get('ioSegmentedResidentFlag'), 0) == 1 and fused == 1 and post_cpu == 0 else 'segmented_resident=FAIL')
        if math.isfinite(kbt_after):
            ok = ok and abs(kbt_after - 1.0e-3) <= 2e-12
            checks.append('kBT=OK' if abs(kbt_after - 1.0e-3) <= 2e-12 else 'kBT=CHECK')
        rows_out.append({
            'validator': label,
            'caseName': r.get('caseName',''),
            'grid': r.get('grid',''),
            'steps': r.get('steps',''),
            'verdict': verdict,
            'failed_metrics': failed,
            'compared_metrics': compared,
            'totalWallSpeedup': '' if not math.isfinite(speedup) else f'{speedup:.6g}',
            'fusedSrcThermostatUse': fused,
            'postCpuThermostatPersistent0258': post_cpu,
            'thermostatGpuAppliedFraction': '' if not math.isfinite(thermo_gpu) else f'{thermo_gpu:.6g}',
            'thermostatActiveCalls': thermo_calls,
            'thermostatKBTBeforeMean': r.get('thermostatKBTBeforeMean',''),
            'thermostatKBTAfterMean': r.get('thermostatKBTAfterMean',''),
            'ioFullfaceResidentFlag': r.get('ioFullfaceResidentFlag',''),
            'ioSegmentedResidentFlag': r.get('ioSegmentedResidentFlag',''),
            'consolidatedStatus': 'PASS' if ok else 'FAIL',
            'checks': ';'.join(checks),
            'sourceCsv': path,
        })
        if not ok:
            errors.append(f"{label} {r.get('grid','?')}: failed consolidated checks: {';'.join(checks)}")

header=['validator','caseName','grid','steps','verdict','failed_metrics','compared_metrics','totalWallSpeedup',
        'fusedSrcThermostatUse','postCpuThermostatPersistent0258','thermostatGpuAppliedFraction',
        'thermostatActiveCalls','thermostatKBTBeforeMean','thermostatKBTAfterMean',
        'ioFullfaceResidentFlag','ioSegmentedResidentFlag','consolidatedStatus','checks','sourceCsv']
os.makedirs(os.path.dirname(out_csv), exist_ok=True)
with open(out_csv, 'w', newline='') as fh:
    w=csv.DictWriter(fh, fieldnames=header)
    w.writeheader(); w.writerows(rows_out)

all_pass = rows_out and not errors and all(r['consolidatedStatus'] == 'PASS' for r in rows_out)
with open(out_summary, 'w') as fh:
    fh.write('CUDA thermostat consolidated validation 0281\n')
    fh.write(f'result={"PASS" if all_pass else "FAIL"}\n')
    fh.write(f'rows={len(rows_out)}\n')
    if errors:
        fh.write('errors:\n')
        for e in errors:
            fh.write(f'- {e}\n')
    else:
        fh.write('errors=none\n')
    fh.write(f'csv={out_csv}\n')

print(f'[0281-consolidated] wrote {out_csv}')
print(f'[0281-consolidated] wrote {out_summary}')
print(f'[0281-consolidated] verdict={"PASS" if all_pass else "FAIL"}')
if not all_pass:
    raise SystemExit(1)
PY

cat "$OUT_SUMMARY"
