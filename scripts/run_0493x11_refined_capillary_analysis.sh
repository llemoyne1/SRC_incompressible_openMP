#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

ACTIVE_YL="${ACTIVE_YL:-runs/0493x11a_young_laplace/manifest.csv}"
BASELINE_YL="${BASELINE_YL:-runs/0493x11a_young_laplace_sigma0/manifest.csv}"
WAVE_CASES="${WAVE_CASES:-runs/0493x11b_capillary_wave/analysis/capillary_wave_cases.csv}"

if [[ -s "$ACTIVE_YL" && -s "$BASELINE_YL" ]]; then
  python3 scripts/analyze_0493x11a_young_laplace_paired.py \
    --active-manifest "$ACTIVE_YL" \
    --baseline-manifest "$BASELINE_YL" \
    --output-dir "$(dirname "$ACTIVE_YL")/analysis_refined"
else
  echo "[0493x11c] Young-Laplace paired analysis skipped: need $ACTIVE_YL and $BASELINE_YL"
fi

if [[ -s "$WAVE_CASES" ]]; then
  python3 scripts/analyze_0493x11b_capillary_wave_earlyfit.py \
    --cases-csv "$WAVE_CASES" \
    --output-dir "$(dirname "$WAVE_CASES")/refined"
else
  echo "[0493x11c] capillary-wave refined analysis skipped: missing $WAVE_CASES"
fi
