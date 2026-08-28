#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"
BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_livevis_0486}"
for f in \
  scripts/run_0493x13i_kbt_scaling.sh \
  scripts/analyze_0493x13i_kbt_scaling.py \
  scripts/generate_0493x13h_shear_state.py \
  scripts/generate_0493x13h_sound_state_fractional.py \
  scripts/generate_0493w1_src_fluid_calibrator_states.py \
  scripts/analyze_0493x13b_constitutive_transport.py \
  scripts/analyze_0493x13h_A_Cdamp_L072.py \
  scripts/analyze_0493w1_src_fluid_calibrator.py; do
  [[ -f "$f" ]] || { echo "[0493x13i-check] missing $f" >&2; exit 2; }
done
[[ -x "$BIN" ]] || { echo "[0493x13i-check] missing/non-executable binary: $BIN" >&2; exit 2; }
bash -n scripts/run_0493x13i_kbt_scaling.sh
python3 -m py_compile scripts/analyze_0493x13i_kbt_scaling.py
python3 scripts/analyze_0493x13i_kbt_scaling.py --help >/dev/null
TMP_ROOT="runs/.check_0493x13i_kbt_scaling_$$"
trap 'rm -rf "$TMP_ROOT"' EXIT
PREFLIGHT_ONLY=1 STAGES=S CAMPAIGN_ROOT="$TMP_ROOT/shear" LIVE_PROGRESS=1 LIVE_VIS_ENABLE=1 LIVE_VIS_EVERY=1 \
  bash scripts/run_0493x13i_kbt_scaling.sh
PREFLIGHT_ONLY=1 STAGES=C,M CAMPAIGN_ROOT="$TMP_ROOT/other" LIVE_PROGRESS=1 LIVE_VIS_ENABLE=1 LIVE_VIS_EVERY=1 \
  bash scripts/run_0493x13i_kbt_scaling.sh
echo '[0493x13i-check] PASS syntax+imports+binary+campaign-preflight'
