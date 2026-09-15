#!/usr/bin/env bash
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT" || exit $?
PATCH="patches/0493x18d_global_mobile_solid_cleanup.patch"

if [ ! -f "$PATCH" ]; then
    echo "[0493x18d] missing patch: $PATCH" >&2
    exit 2
fi

if patch -p1 --dry-run < "$PATCH" >/dev/null 2>&1; then
    patch -p1 < "$PATCH" || exit $?
    echo "[0493x18d] global mobile-solid cleanup applied"
elif patch -R -p1 --dry-run < "$PATCH" >/dev/null 2>&1; then
    echo "[0493x18d] patch already applied"
else
    echo "[0493x18d] patch does not apply cleanly to this tree" >&2
    exit 3
fi
