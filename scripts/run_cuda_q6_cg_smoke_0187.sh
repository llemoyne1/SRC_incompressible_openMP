#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

: "${BUILD:=1}"
: "${NX:=64}"
: "${NY:=48}"
: "${MAX_IT:=1000}"
: "${TOLERANCE:=1e-11}"
: "${PHI_TOLERANCE:=1e-8}"
: "${OUT_DIR:=dev_history/artifacts/gpu_cuda_cg_0187}"
: "${RUN_0186_PRIMITIVE_SMOKE:=1}"
: "${CHECK_FULL_Q6_CUDA_REQUEST_FAILS:=1}"

mkdir -p "$OUT_DIR"

if [[ "$BUILD" == "1" ]]; then
  bash scripts/build_cuda_q6_cg_0187.sh
fi

if [[ "$RUN_0186_PRIMITIVE_SMOKE" == "1" ]]; then
  echo "[0187-cuda-cg-smoke] re-running 0186 primitive smoke first"
  OUT_DIR="dev_history/artifacts/gpu_cuda_backend_0186" \
  CHECK_FULL_Q6_CUDA_REQUEST_FAILS=0 \
  NX="$NX" NY="$NY" TOLERANCE="1e-10" \
  bash scripts/run_cuda_q6_backend_smoke_0186.sh
fi

LOG="$OUT_DIR/cuda_q6_cg_smoke_0187.log"
CSV="$OUT_DIR/cuda_q6_cg_smoke_0187.csv"

echo "[0187-cuda-cg-smoke] running standalone CUDA CG: ${NX}x${NY}, maxIt=${MAX_IT}, tolerance=${TOLERANCE}"
./build/validate_cuda_q6_cg_0187 \
  --nx "$NX" \
  --ny "$NY" \
  --max-it "$MAX_IT" \
  --tolerance "$TOLERANCE" \
  --phi-tolerance "$PHI_TOLERANCE" | tee "$LOG"

python3 - "$LOG" "$CSV" <<'PY'
import csv
import sys
from pathlib import Path

log = Path(sys.argv[1]).read_text(encoding='utf-8', errors='replace').strip().splitlines()
out = Path(sys.argv[2])
record = {'status': 'missing'}
for line in reversed(log):
    if line.startswith('CUDA_Q6_CG_0187 '):
        parts = line.split()
        record['status'] = parts[1]
        for token in parts[2:]:
            if '=' in token:
                k, v = token.split('=', 1)
                record[k] = v
        break
keys = [
    'status','nx','ny','numCells','device','blocks','threadsPerBlock',
    'cpuConverged','cudaConverged','cpuIterations','cudaIterations',
    'cpuResidualRel','cudaResidualRel','exactCpuMaxAbs','exactCudaMaxAbs',
    'cpuCudaMaxAbs','cpuCudaRms','cpuCudaRelRms','tolerance','phiTolerance'
]
out.parent.mkdir(parents=True, exist_ok=True)
with out.open('w', newline='', encoding='utf-8') as f:
    w = csv.DictWriter(f, fieldnames=keys)
    w.writeheader()
    w.writerow({k: record.get(k, '') for k in keys})
if record.get('status') != 'PASS':
    raise SystemExit(1)
PY

echo "[0187-cuda-cg-smoke] wrote $CSV"

if [[ "$CHECK_FULL_Q6_CUDA_REQUEST_FAILS" == "1" ]]; then
  echo "[0187-cuda-cg-smoke] checking that full projectionBackend=cuda is still not silently routed to CPU"
  if [[ ! -x build/src_mpcd_base ]]; then
    bash scripts/build_src_mpcd_base.sh
  fi
  set +e
  PROJECTION_BACKEND=cuda \
  RUN_TAG=cuda_full_q6_expected_fail_0187 \
  RUN_ROOT=runs/cuda_full_q6_expected_fail_0187 \
  THREADS=2 STEPS=1 SUMMARY_EVERY=1 NX=16 NY=16 GAMMA=4 CASE_LIST=tg_periodic_full \
  bash scripts/run_validation_mono_config_0162.sh >"$OUT_DIR/full_q6_cuda_request_stdout_0187.log" 2>"$OUT_DIR/full_q6_cuda_request_stderr_0187.log"
  status=$?
  set -e
  if [[ "$status" == "0" ]]; then
    echo "[0187-cuda-cg-smoke] ERROR: projectionBackend=cuda unexpectedly succeeded in the full Q6 path." >&2
    exit 1
  fi
  if ! grep -R "projectionBackend=cuda" "$OUT_DIR/full_q6_cuda_request_stderr_0187.log" runs/cuda_full_q6_expected_fail_0187 >/dev/null 2>&1; then
    echo "[0187-cuda-cg-smoke] ERROR: full Q6 CUDA rejection did not contain the expected explicit message." >&2
    cat "$OUT_DIR/full_q6_cuda_request_stderr_0187.log" >&2 || true
    exit 1
  fi
  echo "[0187-cuda-cg-smoke] PASS: full projectionBackend=cuda still fails explicitly until the standalone CG is wired."
fi

echo "[0187-cuda-cg-smoke] PASS"
