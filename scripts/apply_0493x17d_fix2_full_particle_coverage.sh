#!/usr/bin/env bash
set -u

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT" || exit $?
PATCH="patches/0493x17d_fix2_full_particle_coverage.patch"

[[ -f "$PATCH" ]] || { echo "[0493x17d-fix2] ERROR missing $PATCH" >&2; exit 2; }
[[ -f src/cuda_q6_resident_0400.cu ]] || { echo "[0493x17d-fix2] ERROR run from repository root" >&2; exit 2; }

if patch --dry-run -p1 < "$PATCH" >/dev/null 2>&1; then
  patch -p1 < "$PATCH" || exit $?
  echo "[0493x17d-fix2] source patch applied"
elif patch --dry-run -R -p1 < "$PATCH" >/dev/null 2>&1; then
  echo "[0493x17d-fix2] source patch already present; no source change"
else
  echo "[0493x17d-fix2] ERROR patch matches neither pre-fix nor already-fixed source" >&2
  exit 3
fi

bash scripts/check_0493x17d_fix2_full_particle_coverage.sh || exit $?
echo "[0493x17d-fix2] APPLY PASS"
