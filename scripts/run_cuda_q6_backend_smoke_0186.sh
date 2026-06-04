#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

: "${BUILD:=1}"
: "${NX:=64}"
: "${NY:=48}"
: "${TOLERANCE:=1e-10}"
: "${OUT_DIR:=dev_history/artifacts/gpu_cuda_backend_0186}"
: "${CHECK_FULL_Q6_CUDA_REQUEST_FAILS:=1}"

mkdir -p "$OUT_DIR"

if [[ "$BUILD" == "1" ]]; then
  bash scripts/build_cuda_q6_backend_0186.sh
fi

LOG="$OUT_DIR/cuda_q6_backend_smoke_0186.log"
CSV="$OUT_DIR/cuda_q6_backend_smoke_0186.csv"

echo "[0186-cuda-smoke] running CUDA elliptic operator primitive: ${NX}x${NY}, tolerance=${TOLERANCE}"
./build/validate_cuda_q6_backend_0186 --nx "$NX" --ny "$NY" --tolerance "$TOLERANCE" | tee "$LOG"

python3 - "$LOG" "$CSV" <<'PY'
import csv
import sys
from pathlib import Path

log = Path(sys.argv[1]).read_text(encoding='utf-8', errors='replace').strip().splitlines()
out = Path(sys.argv[2])
record = {'status': 'missing'}
for line in reversed(log):
    if line.startswith('CUDA_Q6_BACKEND_0186 '):
        parts = line.split()
        record['status'] = parts[1]
        for token in parts[2:]:
            if '=' in token:
                k, v = token.split('=', 1)
                record[k] = v
        break
keys = ['status','nx','ny','numCells','device','blocks','threadsPerBlock','pApCpu','pApCuda','relPApDiff','maxAbsAphiDiff','rmsAphiDiff','tolerance']
out.parent.mkdir(parents=True, exist_ok=True)
with out.open('w', newline='', encoding='utf-8') as f:
    w = csv.DictWriter(f, fieldnames=keys)
    w.writeheader()
    w.writerow({k: record.get(k, '') for k in keys})
if record.get('status') != 'PASS':
    raise SystemExit(1)
PY

echo "[0186-cuda-smoke] wrote $CSV"

if [[ "$CHECK_FULL_Q6_CUDA_REQUEST_FAILS" == "1" ]]; then
  echo "[0186-cuda-smoke] checking that full projectionBackend=cuda is still not silently routed to CPU"
  if [[ ! -x build/src_mpcd_base ]]; then
    bash scripts/build_src_mpcd_base.sh
  fi
  set +e
  PROJECTION_BACKEND=cuda \
  RUN_TAG=cuda_full_q6_expected_fail_0186 \
  RUN_ROOT=runs/cuda_full_q6_expected_fail_0186 \
  THREADS=2 STEPS=1 SUMMARY_EVERY=1 NX=16 NY=16 GAMMA=4 CASE_LIST=tg_periodic_full \
  bash scripts/run_validation_mono_config_0162.sh >"$OUT_DIR/full_q6_cuda_request_stdout_0186.log" 2>"$OUT_DIR/full_q6_cuda_request_stderr_0186.log"
  status=$?
  set -e
  if [[ "$status" == "0" ]]; then
    echo "[0186-cuda-smoke] ERROR: projectionBackend=cuda unexpectedly succeeded in the full Q6 path." >&2
    exit 1
  fi
  if ! grep -R "projectionBackend=cuda" "$OUT_DIR/full_q6_cuda_request_stderr_0186.log" runs/cuda_full_q6_expected_fail_0186 >/dev/null 2>&1; then
    echo "[0186-cuda-smoke] ERROR: full Q6 CUDA rejection did not contain the expected explicit message." >&2
    cat "$OUT_DIR/full_q6_cuda_request_stderr_0186.log" >&2 || true
    exit 1
  fi
  echo "[0186-cuda-smoke] PASS: full projectionBackend=cuda still fails explicitly until the CG path is wired."
fi

echo "[0186-cuda-smoke] PASS"
