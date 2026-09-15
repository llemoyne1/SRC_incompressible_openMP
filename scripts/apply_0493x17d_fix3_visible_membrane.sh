#!/usr/bin/env bash
set -u
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT" || exit $?
PATCH="patches/0493x17d_fix3_visible_membrane.patch"
[[ -f "$PATCH" ]] || { echo "[0493x17d-fix3] ERROR missing $PATCH" >&2; exit 2; }
[[ -f src/cuda_q6_resident_0400.cu ]] || { echo "[0493x17d-fix3] ERROR run from repository root" >&2; exit 2; }
if patch --dry-run -p1 < "$PATCH" >/dev/null 2>&1; then
  patch -p1 < "$PATCH" || exit $?
  echo "[0493x17d-fix3] source patch applied"
elif patch --dry-run -R -p1 < "$PATCH" >/dev/null 2>&1; then
  echo "[0493x17d-fix3] source patch already present; no source change"
else
  echo "[0493x17d-fix3] ERROR patch matches neither fix2 source nor already-fixed source" >&2
  exit 3
fi
bash scripts/check_0493x17d_fix3_visible_membrane.sh || exit $?
echo "[0493x17d-fix3] APPLY PASS"
