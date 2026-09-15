#!/usr/bin/env bash
set -u
ROOT="${ROOT:-$(pwd)}"
cd "$ROOT" || exit 2
PATCH="patches/0493x18a_fix2_initial_angle_fluid.patch"
TARGET="scripts/run_0493x18a_hinged_plate.sh"
if patch --dry-run -p1 < "$PATCH" >/dev/null 2>&1; then
  patch -p1 < "$PATCH" || exit $?
  echo "[0493x18a-fix2] applied runner initial-fluid geometry fix"
elif patch --dry-run -R -p1 < "$PATCH" >/dev/null 2>&1; then
  echo "[0493x18a-fix2] runner patch already applied"
else
  echo "[0493x18a-fix2] ERROR patch does not apply cleanly to $TARGET" >&2
  echo "The patch does not touch FLOW_UX/STEPS defaults, so user edits there are normally preserved." >&2
  exit 2
fi
bash -n "$TARGET" || exit $?
python3 -m py_compile scripts/prepare_0493x18a_initial_fluid.py || exit $?
echo "[0493x18a-fix2] verification PASS"
