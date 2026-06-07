#!/usr/bin/env bash
set -euo pipefail

# 0286 — consolidated SRC classic full-CUDA validation wrapper.
#
# Scope:
#   SRC classic = advection/streaming + random shift + SRC rotation/collision + thermostat.
#   Q6, resampling and virial/capacity closure are not part of the classic fused path.
#
# The wrapper reuses the validated discriminant validators:
#   0281: wall, rectangle/solid, piston/mobile wall, IO full-face, IO segmented
#   0284: periodic circular immersed solid
#   0285: circular immersed solid + full-face inlet/outlet / cylinder wake setup

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BIN=${BIN:-build/src_mpcd_base_cuda_0286}
ART_DIR=${ART_DIR:-dev_history/artifacts/gpu_cuda_src_classic_full_consolidated_0286}
GRID_CASES=${GRID_CASES:-"64:64:300 128:128:300"}
FORCE_REBUILD=${FORCE_REBUILD:-1}
STOP_ON_FAIL=${STOP_ON_FAIL:-1}

mkdir -p "$ART_DIR"
SUMMARY_TXT="$ART_DIR/cuda_src_classic_full_consolidated_0286_summary.txt"
COMBINED_CSV="$ART_DIR/cuda_src_classic_full_consolidated_0286_manifest.csv"

if [[ "$FORCE_REBUILD" != "0" && "$FORCE_REBUILD" != "false" && "$FORCE_REBUILD" != "FALSE" ]]; then
  echo "[0286-consolidated] rebuilding $BIN"
  OUT="$BIN" CUDA_ARCH_FLAGS="${CUDA_ARCH_FLAGS:-}" bash scripts/build_src_mpcd_cuda_0286.sh
elif [[ ! -x "$BIN" ]]; then
  echo "[0286-consolidated] binary missing, building $BIN"
  OUT="$BIN" CUDA_ARCH_FLAGS="${CUDA_ARCH_FLAGS:-}" bash scripts/build_src_mpcd_cuda_0286.sh
fi

if [[ ! -x "$BIN" ]]; then
  echo "[0286-consolidated] ERROR: missing binary $BIN" >&2
  exit 127
fi

run_phase() {
  local phase=$1
  local script=$2
  local expected_csv=$3
  echo "[0286-consolidated] =========================================="
  echo "[0286-consolidated] phase=$phase script=$script"
  echo "[0286-consolidated] =========================================="
  set +e
  BIN="$BIN" GRID_CASES="$GRID_CASES" FORCE_REBUILD=0 STOP_ON_FAIL="$STOP_ON_FAIL" bash "$script"
  local rc=$?
  set -e
  if [[ $rc -ne 0 ]]; then
    echo "[0286-consolidated] FAIL phase=$phase rc=$rc" >&2
    return $rc
  fi
  if [[ ! -s "$expected_csv" ]]; then
    echo "[0286-consolidated] FAIL phase=$phase missing expected CSV: $expected_csv" >&2
    return 98
  fi
  echo "[0286-consolidated] PASS phase=$phase csv=$expected_csv"
}

run_phase "thermostat_boundary_0281" \
  "scripts/run_cuda_persistent_src_thermostat_consolidated_0281.sh" \
  "dev_history/artifacts/gpu_cuda_persistent_src_thermostat_consolidated_0281/cuda_persistent_src_thermostat_consolidated_0281.csv"

run_phase "periodic_circle_0284" \
  "scripts/run_cuda_persistent_src_thermostat_circle_0284.sh" \
  "dev_history/artifacts/gpu_cuda_persistent_src_thermostat_circle_0284/cuda_persistent_src_thermostat_circle_0284.csv"

run_phase "circle_io_fullface_0285" \
  "scripts/run_cuda_persistent_src_thermostat_circle_io_0285.sh" \
  "dev_history/artifacts/gpu_cuda_persistent_src_thermostat_circle_io_0285/cuda_persistent_src_thermostat_circle_io_0285.csv"

python3 - "$COMBINED_CSV" <<'PY'
import csv, pathlib, sys
out = pathlib.Path(sys.argv[1])
inputs = [
    ('thermostat_boundary_0281', pathlib.Path('dev_history/artifacts/gpu_cuda_persistent_src_thermostat_consolidated_0281/cuda_persistent_src_thermostat_consolidated_0281.csv')),
    ('periodic_circle_0284', pathlib.Path('dev_history/artifacts/gpu_cuda_persistent_src_thermostat_circle_0284/cuda_persistent_src_thermostat_circle_0284.csv')),
    ('circle_io_fullface_0285', pathlib.Path('dev_history/artifacts/gpu_cuda_persistent_src_thermostat_circle_io_0285/cuda_persistent_src_thermostat_circle_io_0285.csv')),
]
rows=[]
for phase, path in inputs:
    with path.open(newline='') as fh:
        reader = csv.DictReader(fh)
        for r in reader:
            rows.append({
                'phase': phase,
                'caseName': r.get('caseName',''),
                'grid': r.get('grid',''),
                'steps': r.get('steps',''),
                'mode': r.get('mode',''),
                'failed_metrics': r.get('failed_metrics',''),
                'compared_metrics': r.get('compared_metrics',''),
                'verdict': r.get('verdict',''),
                'totalWallSpeedup': r.get('totalWallSpeedup',''),
                'thermostatGpuAppliedFraction': r.get('thermostatGpuAppliedFraction',''),
                'fusedSrcThermostatUse': r.get('fusedSrcThermostatUse',''),
                'ioFullfaceResidentFlag': r.get('ioFullfaceResidentFlag',''),
                'ioSegmentedResidentFlag': r.get('ioSegmentedResidentFlag',''),
                'immersedCircleFlag': r.get('immersedCircleFlag',''),
            })
with out.open('w', newline='') as fh:
    writer = csv.DictWriter(fh, fieldnames=list(rows[0].keys()) if rows else ['phase'])
    writer.writeheader(); writer.writerows(rows)
PY

python3 - "$COMBINED_CSV" "$SUMMARY_TXT" <<'PY'
import csv, pathlib, sys
manifest=pathlib.Path(sys.argv[1])
summary=pathlib.Path(sys.argv[2])
with manifest.open(newline='') as fh:
    rows=list(csv.DictReader(fh))
errors=[]
for r in rows:
    if r.get('verdict') != 'PASS':
        errors.append(f"{r.get('phase')} {r.get('caseName')} {r.get('grid')} verdict={r.get('verdict')}")
    try:
        if int(float(r.get('failed_metrics') or '999999')) != 0:
            errors.append(f"{r.get('phase')} {r.get('caseName')} {r.get('grid')} failed={r.get('failed_metrics')}")
    except Exception:
        errors.append(f"{r.get('phase')} {r.get('caseName')} {r.get('grid')} failed_metrics_unreadable")
text = []
text.append('CUDA SRC classic full consolidated validation 0286')
text.append(f"result={'PASS' if not errors and rows else 'FAIL'}")
text.append(f"rows={len(rows)}")
text.append('errors=' + ('none' if not errors else '; '.join(errors)))
text.append(f"manifest={manifest}")
summary.write_text('\n'.join(text) + '\n')
print('\n'.join(text))
if errors or not rows:
    raise SystemExit(1)
PY

echo "[0286-consolidated] wrote $COMBINED_CSV"
echo "[0286-consolidated] wrote $SUMMARY_TXT"
