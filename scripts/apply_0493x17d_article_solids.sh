#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"; cd "$ROOT"
PATCH=patches/0493x17d_article_solid_dynamics.patch
[[ -f "$PATCH" ]] || { echo "[0493x17d] ERROR missing $PATCH" >&2; exit 2; }
if grep -q 'closed-loop-parity+nearest-edge-depth' src/cuda_q6_resident_0400.cu 2>/dev/null && grep -q 'chiSolidMembraneAnchorMode = "none"' include/simulation_params.h 2>/dev/null; then
  echo '[0493x17d] source patch already present; skipping patch application'
else
  patch --dry-run -p1 < "$PATCH"
  patch -p1 < "$PATCH"
fi
bash scripts/check_0493x17d_article_solids.sh
echo '[0493x17d] APPLY PASS'
