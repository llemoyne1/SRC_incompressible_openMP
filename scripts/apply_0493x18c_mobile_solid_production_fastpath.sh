#!/usr/bin/env bash

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
PATCH_FILE="$ROOT/patches/0493x18c_mobile_solid_production_fastpath.patch"

cd "$ROOT" || exit $?

if [ ! -f "$PATCH_FILE" ]; then
    echo "[0493x18c] ERROR missing patch: $PATCH_FILE" >&2
    exit 2
fi

if patch -p1 --dry-run < "$PATCH_FILE" >/dev/null 2>&1; then
    echo "[0493x18c] applying production fast-path patch"
    patch -p1 < "$PATCH_FILE" || exit $?
    echo "[0493x18c] patch applied"
    exit 0
fi

if patch -p1 -R --dry-run < "$PATCH_FILE" >/dev/null 2>&1; then
    echo "[0493x18c] patch already applied"
    exit 0
fi

echo "[0493x18c] ERROR patch is neither directly applicable nor already applied." >&2
echo "[0493x18c] Inspect local modifications before forcing any merge." >&2
exit 2
