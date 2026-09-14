#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(pwd)}"
cd "$ROOT"
PATCH=patches/0493x16n_q2_dual_square_consistency.patch
CHECK=scripts/check_0493x16n_q2_dual_square_consistency.sh
SRC=src/cuda_q6_resident_0400.cu

[[ -f "$PATCH" ]] || { echo "[0493x16n] missing $PATCH" >&2; exit 2; }
[[ -f "$SRC" ]] || { echo "[0493x16n] missing $SRC" >&2; exit 2; }

if grep -q 'q2Owner=x16n-dual-square-clipped' "$SRC"; then
  echo '[0493x16n] patch already applied; validating'
  bash "$CHECK"
  exit 0
fi

grep -q 'q2Root=x16m-bisection-1e-8cell' "$SRC" || {
  echo '[0493x16n] ERROR x16m prerequisite not found' >&2; exit 3; }
grep -q '0493x16l-penetration' "$SRC" || {
  echo '[0493x16n] ERROR x16l prerequisite not found' >&2; exit 3; }
grep -q 'SRC_X16I_STATIC_CURVED_0493X16M' src/cuda_chi_solid_0493x16e.cu || {
  echo '[0493x16n] ERROR static-curved characterization prerequisite not found' >&2; exit 3; }

patch --dry-run -p1 < "$PATCH"
patch -p1 < "$PATCH"
chmod +x \
  scripts/check_0493x16n_q2_dual_square_consistency.sh \
  scripts/check_0493x16n_q2_dual_square_math.py \
  scripts/run_0493x16n_q2_dual_square_qualification.sh \
  scripts/analyze_0493x16n_q2_dual_square_qualification.py
bash "$CHECK"
echo '[0493x16n] APPLY PASS'
