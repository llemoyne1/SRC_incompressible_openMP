#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

RUNNER=scripts/run_0493x12yl_young_laplace_calibrator.sh
ANALYZER=scripts/analyze_0493x12yl_young_laplace_calibrator.py
PARENT=scripts/run_0493x10o_q6_thermal_interface_static_drop.sh

for f in "$RUNNER" "$ANALYZER" "$PARENT" scripts/run_0493x9s_splash.sh src/cuda_q6_resident_0400.cu; do
  [[ -f "$f" ]] || { echo "[0493x12yl-check] ERROR missing $f" >&2; exit 2; }
done

bash -n "$RUNNER"
python3 -m py_compile "$ANALYZER"
python3 "$ANALYZER" --self-test

for marker in \
  'MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE_SWAP' \
  'MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE' \
  'MPCD_X10_KINETIC_INTERFACE_QUADRATIC' \
  'MPCD_X10_KINETIC_INTERFACE_CIC' \
  'MPCD_X12A_LOCAL_THERMAL_COOLING'; do
  grep -q "$marker" src/cuda_q6_resident_0400.cu || {
    echo "[0493x12yl-check] ERROR source missing production marker: $marker" >&2
    exit 2
  }
done

grep -q 'MPCD_X11C_FORCE_X9E_SIGMA0' scripts/run_0493x9s_splash.sh || {
  echo "[0493x12yl-check] ERROR x9s lacks sigma=0 x9e diagnostic support" >&2
  exit 2
}

# Contract checks: the calibrator must measure the exact current chain, not an
# ablation.  No source modification is performed by these scripts.
for contract in \
  'export MPCD_X10O_Q6_THERMAL_INTERFACE_WALL=1' \
  'export MPCD_X10_KINETIC_INTERFACE_CIC=1' \
  'export MPCD_X10_KINETIC_INTERFACE_QUADRATIC=1' \
  'export MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE=1' \
  'export MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE_SWAP=1' \
  'export MPCD_X12A_LOCAL_THERMAL_COOLING=1'; do
  grep -qF "$contract" "$RUNNER" || {
    echo "[0493x12yl-check] ERROR runner contract missing: $contract" >&2
    exit 2
  }
done

PREFLIGHT_ONLY=1 PROFILE=quick SIGMA_DECLARED=945 LIVE_VIS_ENABLE=0 \
  bash "$RUNNER"

echo "[0493x12yl-check] PASS syntax+self-test+production-chain+paired-sigma0+preflight"
