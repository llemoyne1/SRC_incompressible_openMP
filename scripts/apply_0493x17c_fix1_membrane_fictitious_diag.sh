#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"
P=patches/0493x17c_fix1_membrane_fictitious_diag_140926.patch
[[ -f "$P" ]] || { echo "[0493x17c-fix1] missing $P" >&2; exit 2; }
grep -q '0493x17c-membrane' src/cuda_q6_resident_0400.cu || {
  echo '[0493x17c-fix1] prerequisite absent: apply x17c first' >&2; exit 2; }
if grep -q '0493x17c-fix1: x16c is a fictitious-domain inventory diagnostic' src/cuda_darcy_brinkman_0343.cu; then
  echo '[0493x17c-fix1] already applied; checking'
  bash scripts/check_0493x17c_fix1_membrane_fictitious_diag.sh
  exit 0
fi
patch --dry-run -p1 < "$P"
patch -p1 < "$P"
bash scripts/check_0493x17c_fix1_membrane_fictitious_diag.sh
echo '[0493x17c-fix1] APPLY PASS'
