#!/usr/bin/env bash
set -euo pipefail

# 0190 — regression for the CUDA Q6 integrated Taylor--Green subset after
# launch-overhead cleanup. The strict full-run CPU/CUDA metric comparison is
# still written, but the pass criterion focuses on Q6 correctness.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BIN=${BIN:-build/src_mpcd_base_cuda_0190}
RUN_ROOT_CPU=${RUN_ROOT_CPU:-runs/cuda_q6_tg_cpu_ref_0190}
RUN_ROOT_CUDA=${RUN_ROOT_CUDA:-runs/cuda_q6_tg_cuda_0190}
ART_DIR=${ART_DIR:-dev_history/artifacts/gpu_cuda_integration_0190}
COMPARE_OUT=${COMPARE_OUT:-$ART_DIR/cuda_q6_tg_compare_0190.csv}
COMPARE_SUMMARY_OUT=${COMPARE_SUMMARY_OUT:-$ART_DIR/cuda_q6_tg_compare_summary_0190.csv}
CUDA_Q6_DIV_AFTER_MAX=${CUDA_Q6_DIV_AFTER_MAX:-1e-8}
CUDA_Q6_MIN_ITERATIONS=${CUDA_Q6_MIN_ITERATIONS:-26}
CHECK_UNSUPPORTED=${CHECK_UNSUPPORTED:-1}

mkdir -p "$ART_DIR"

if [[ ! -x "$BIN" ]]; then
  OUT="$BIN" CUDA_ARCH_FLAGS=${CUDA_ARCH_FLAGS:-} bash scripts/build_src_mpcd_cuda_0190.sh
fi
if [[ ! -x "$BIN" ]]; then
  echo "[0190-cuda-tg] ERROR: CUDA-enabled binary not found after build: $BIN" >&2
  exit 127
fi

COMMON_ENV=(
  BIN="$BIN"
  BUILD_IF_MISSING=0
  CASE_LIST="tg_periodic_full"
  NX="${NX:-64}"
  NY="${NY:-64}"
  GAMMA="${GAMMA:-20}"
  STEPS="${STEPS:-1000}"
  SUMMARY_EVERY="${SUMMARY_EVERY:-100}"
  THREADS="${THREADS:-8}"
  SEED="${SEED:-1620189}"
  DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-0}"
)

echo "[0190-cuda-tg] CPU reference run: $RUN_ROOT_CPU"
env "${COMMON_ENV[@]}" \
  RUN_ROOT="$RUN_ROOT_CPU" \
  RUN_TAG="cuda0190_cpu_reference" \
  PROJECTION_BACKEND=cpu \
  bash scripts/run_validation_mono_config_0162.sh

echo "[0190-cuda-tg] CUDA run: $RUN_ROOT_CUDA"
env "${COMMON_ENV[@]}" \
  RUN_ROOT="$RUN_ROOT_CUDA" \
  RUN_TAG="cuda0190_cuda_periodic" \
  PROJECTION_BACKEND=cuda \
  MPCD_CUDA_Q6_DEBUG_SYNC="${MPCD_CUDA_Q6_DEBUG_SYNC:-0}" \
  bash scripts/run_validation_mono_config_0162.sh

python3 scripts/compare_validation_mono_config_0162.py \
  --origin "$RUN_ROOT_CPU" \
  --optimized "$RUN_ROOT_CUDA" \
  --out "$COMPARE_OUT" \
  --summary-out "$COMPARE_SUMMARY_OUT"

python3 - "$RUN_ROOT_CUDA/validation_summary_0162.csv" "$CUDA_Q6_DIV_AFTER_MAX" "$CUDA_Q6_MIN_ITERATIONS" <<'PY'
import csv
import math
import sys

summary_path, div_max_s, min_it_s = sys.argv[1:4]
div_max = float(div_max_s)
min_it = int(min_it_s)
with open(summary_path, newline="") as f:
    rows = list(csv.DictReader(f))
if len(rows) != 1:
    raise SystemExit(f"expected one summary row, got {len(rows)} in {summary_path}")
r = rows[0]
q6_applied = int(float(r.get("q6Applied", "0")))
q6_converged = int(float(r.get("q6Converged", "0")))
q6_iter = int(float(r.get("q6Iterations", "0")))
q6_resid = float(r.get("q6ResidualRel", "nan"))
q6_div_after = float(r.get("q6DivAfterProjectedFluxRms", "nan"))
if q6_applied != 1 or q6_converged != 1:
    raise SystemExit(f"CUDA Q6 did not report applied+converged: applied={q6_applied} converged={q6_converged}")
if q6_iter < min_it:
    raise SystemExit(f"CUDA Q6 stopped too early: q6Iterations={q6_iter} < {min_it}; suspected residual-norm regression")
if not math.isfinite(q6_resid) or q6_resid <= 0.0:
    raise SystemExit(f"CUDA Q6 residualRel must be positive and finite after 0190 regression; got {q6_resid}")
if not math.isfinite(q6_div_after) or q6_div_after > div_max:
    raise SystemExit(f"CUDA Q6 divAfter too large: {q6_div_after} > {div_max}")
print(f"[0190-cuda-tg] Q6 regression PASS: iterations={q6_iter} residualRel={q6_resid:.6e} divAfter={q6_div_after:.6e}")
PY

if [[ "$CHECK_UNSUPPORTED" == "1" ]]; then
  echo "[0190-cuda-tg] Checking that non-periodic Poiseuille remains rejected by projectionBackend=cuda."
  FAIL_ROOT=${FAIL_ROOT:-runs/cuda_q6_unsupported_expected_fail_0190}
  rm -rf "$FAIL_ROOT"
  set +e
  env BIN="$BIN" BUILD_IF_MISSING=0 CASE_LIST="poiseuille_wall_full" \
      RUN_ROOT="$FAIL_ROOT" RUN_TAG="cuda0190_expected_unsupported" \
      PROJECTION_BACKEND=cuda NX=16 NY=16 GAMMA=4 STEPS=1 SUMMARY_EVERY=1 THREADS=2 \
      bash scripts/run_validation_mono_config_0162.sh \
      > "$ART_DIR/cuda_q6_unsupported_stdout_0190.log" \
      2> "$ART_DIR/cuda_q6_unsupported_stderr_0190.log"
  status=$?
  set -e
  if [[ $status -eq 0 ]]; then
    echo "[0190-cuda-tg] ERROR: unsupported non-periodic CUDA Q6 case unexpectedly succeeded." >&2
    exit 1
  fi
  if ! grep -R "fully periodic, unmasked" "$ART_DIR/cuda_q6_unsupported_stderr_0190.log" "$FAIL_ROOT" >/dev/null 2>&1; then
    echo "[0190-cuda-tg] ERROR: unsupported-case failure did not contain the expected guard message." >&2
    exit 1
  fi
  echo "[0190-cuda-tg] PASS: unsupported non-periodic CUDA Q6 case failed explicitly."
fi

echo "[0190-cuda-tg] PASS: CUDA Q6 integrated TG regression completed."
echo "[0190-cuda-tg] Compare summary: $COMPARE_SUMMARY_OUT"
