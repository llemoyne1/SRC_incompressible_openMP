#!/usr/bin/env bash
set -u
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT" || exit 1
PATCH="patches/0493x17d_fix6_coherent_strip.patch"
if patch --dry-run -p1 < "$PATCH" >/dev/null 2>&1; then
  patch -p1 < "$PATCH" || exit $?
  echo "[0493x17d-fix6] APPLIED"
elif patch --dry-run -R -p1 < "$PATCH" >/dev/null 2>&1; then
  echo "[0493x17d-fix6] already applied"
else
  echo "[0493x17d-fix6] ERROR patch does not match current x17d-fix3 source" >&2
  exit 2
fi
