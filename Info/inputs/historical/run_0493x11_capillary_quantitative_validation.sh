#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

echo '===== 0493x11 QUANTITATIVE CAPILLARY VALIDATION ====='
echo '1/2 Young-Laplace static drops'
bash scripts/run_0493x11a_young_laplace_validation.sh
echo
echo '2/2 capillary-wave dispersion'
bash scripts/run_0493x11b_capillary_wave_validation.sh
