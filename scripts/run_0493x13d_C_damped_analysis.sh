#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"
X13C_ROOT="${X13C_ROOT:-runs/0493x13c_transport_qualification}"
OUTPUT_ROOT="${OUTPUT_ROOT:-runs/0493x13d_transport_followup/analysis}"
BOOTSTRAP="${BOOTSTRAP:-500}"
CS_MIN="${CS_MIN:-0.20}"
CS_MAX="${CS_MAX:-0.50}"
VALIDATE_LOCAL="${VALIDATE_LOCAL:-1}"
manifest="$X13C_ROOT/C_statistics/manifest_0493x13c_Cstat.csv"
[[ -f "$manifest" ]] || { echo "[0493x13d-C-fastfit-fix1] missing x13c manifest: $manifest" >&2; exit 2; }
args=(
  --repo-root "$ROOT"
  --x13c-root "$X13C_ROOT"
  --output-root "$OUTPUT_ROOT"
  --bootstrap "$BOOTSTRAP"
  --cs-min "$CS_MIN"
  --cs-max "$CS_MAX"
)
if [[ "$VALIDATE_LOCAL" == "1" ]]; then args+=(--validate-local); fi
python3 scripts/analyze_0493x13d_C_damped_mode.py "${args[@]}"
echo "[0493x13d-C-fastfit-fix1] ANALYSIS COMPLETE output=$OUTPUT_ROOT"
