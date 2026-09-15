#!/usr/bin/env bash
set -u
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT" || exit $?
PATCH_FILE="patches/0493x18a_hinged_plate_1dof.patch"
if [ ! -f "$PATCH_FILE" ]; then
  echo "[0493x18a] ERROR missing $PATCH_FILE" >&2
  exit 2
fi
if patch --dry-run -p1 < "$PATCH_FILE" >/dev/null 2>&1; then
  patch -p1 < "$PATCH_FILE" || exit $?
  echo "[0493x18a] source patch applied"
elif patch --dry-run -R -p1 < "$PATCH_FILE" >/dev/null 2>&1; then
  echo "[0493x18a] source patch already applied"
else
  echo "[0493x18a] ERROR patch is neither forward-applicable nor already applied" >&2
  echo "[0493x18a] inspect: git status --short && patch --dry-run -p1 < $PATCH_FILE" >&2
  exit 3
fi
