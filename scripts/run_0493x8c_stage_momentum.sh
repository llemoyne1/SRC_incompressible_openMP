#!/usr/bin/env bash
set -euo pipefail
cd "${ROOT:-/mnt/e/SRC_MPCD_DEV/SRC_GPU-SURF}"

grep -q 'MPCD_MOMENTUM_STAGE_DIAG_0493X8C' src/src_mpcd_base.cpp || {
  echo "[0493x8c] ERROR x8c not installed" >&2; exit 2; }
grep -q 'MPCD_DARCY_EXACT_MOMENTUM_DIAG_0493X8A' src/cuda_darcy_brinkman_0343.cu || {
  echo "[0493x8c] ERROR x8a exact Darcy diagnostic required" >&2; exit 2; }

run_vk() {
  local root="$1" steps="$2" summary="$3" every="$4" maxstep="$5"
  MPCD_MOMENTUM_STAGE_DIAG_0493X8C=1 \
  MPCD_MOMENTUM_STAGE_DIAG_EVERY_0493X8C="$every" \
  MPCD_MOMENTUM_STAGE_DIAG_MAX_STEP_0493X8C="$maxstep" \
  MPCD_DARCY_EXACT_MOMENTUM_DIAG_0493X8A=1 \
  RUN_MODES="src src-q6 src-q6-g-f" \
  NX=750 NY=200 GAMMA=6 DT=0.0005 KBT=5.0 U0=0.9 \
  ROTATION_ANGLE=1.3962634015954636 \
  RUN_OK_DARCY_COMMON_FILLED_STATE=1 \
  BASE_RUN_ROOT="$root" \
  STEPS="$steps" SUMMARY_EVERY="$summary" DUMP_STATE_EVERY="$steps" \
  TOPO_BENCHMARK_ENABLE=true TOPO_BENCHMARK_EVERY="$summary" \
  LIVE_PROGRESS=1 LIVE_VIS_ENABLE=0 LIVE_VIS_HOLD_ON_EXIT=0 \
  FILTERED_RECORDING_ENABLE=0 AUTO_BUILD=0 BUILD_IF_STALE=0 \
  bash scripts/run_ok_vk.sh
}

echo "[0493x8c] smoke"
run_vk runs/0493x8c_smoke_stage_momentum_750 2 1 1 2

python3 - <<'PY'
import csv
from pathlib import Path
root=Path("runs/0493x8c_smoke_stage_momentum_750")
modes=("src","src-q6","src-q6-g-f")
want={"step_start","after_q6_prestream","after_force_stream","after_boundary",
      "after_collision","after_q6_post","after_thermostat","after_darcy_post"}
for mode in modes:
    p=root/mode/"output/momentum_stages_0493x8c.csv"
    if not p.is_file(): raise SystemExit(f"missing {p}")
    rows=list(csv.DictReader(p.open()))
    for step in (1,2):
        got={r["stage"] for r in rows if int(float(r["step"]))==step}
        if got!=want: raise SystemExit(f"{mode} step={step} stages={sorted(got)}")
    d=root/mode/"output/darcy_exact_momentum_0493x8a.csv"
    if not d.is_file(): raise SystemExit(f"missing {d}")
print("[0493x8c-smoke] PASS 3 modes x 2 steps x 8 stages")
PY

echo "[0493x8c] 200-step localization"
run_vk runs/0493x8c_stage_momentum_750 200 20 20 200

python3 scripts/analyze_0493x8c_stage_momentum.py \
  --root runs/0493x8c_stage_momentum_750 \
  --output-dir runs/0493x8c_stage_momentum_750/analysis_x8c
echo "[0493x8c] COMPLETE"
