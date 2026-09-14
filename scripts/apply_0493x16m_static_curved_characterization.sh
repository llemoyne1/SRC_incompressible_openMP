#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"
PATCH="patches/0493x16m_static_curved_characterization.patch"
[[ -f "$PATCH" ]] || { echo "[0493x16m-static-curve] ERROR missing $PATCH" >&2; exit 2; }
grep -q 'q2Root=x16m-bisection-1e-8cell' src/cuda_q6_resident_0400.cu || { echo "[0493x16m-static-curve] ERROR x16m prerequisite absent" >&2; exit 2; }
grep -q 'chi_penetration_0493x16l' src/cuda_q6_resident_0400.cu || { echo "[0493x16m-static-curve] ERROR x16l diagnostic prerequisite absent" >&2; exit 2; }
if grep -q 'SRC_X16I_STATIC_CURVED_0493X16M' src/cuda_chi_solid_0493x16e.cu; then
  echo '[0493x16m-static-curve] source patch already applied; validating'
else
  patch --dry-run -p1 < "$PATCH"
  patch -p1 < "$PATCH"
fi
bash scripts/check_0493x16m_static_curved_characterization.sh
echo '[0493x16m-static-curve] APPLY PASS'
