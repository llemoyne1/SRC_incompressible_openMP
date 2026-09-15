#!/usr/bin/env bash
set -u
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT" || exit $?
PATCH="patches/0493x17d_fix7_bendable_coherent_strip.patch"
if patch -p1 --forward --dry-run < "$PATCH" >/dev/null 2>&1; then
  patch -p1 --forward < "$PATCH" || exit $?
  echo "[0493x17d-fix7] applied"
elif patch -p1 --reverse --dry-run < "$PATCH" >/dev/null 2>&1; then
  echo "[0493x17d-fix7] already applied"
else
  echo "[0493x17d-fix7] ERROR patch neither applies nor reverses cleanly" >&2
  exit 2
fi
