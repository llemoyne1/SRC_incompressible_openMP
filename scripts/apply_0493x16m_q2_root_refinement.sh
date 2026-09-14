#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(pwd)}"
cd "$ROOT"
PATCH=patches/0493x16m_q2_root_refinement.patch
CHECK=scripts/check_0493x16m_q2_root_refinement.sh
SRC=src/cuda_q6_resident_0400.cu

[[ -f "$PATCH" ]] || { echo "[0493x16m] missing $PATCH" >&2; exit 2; }
[[ -f "$SRC" ]] || { echo "[0493x16m] missing $SRC" >&2; exit 2; }

# x16m is intentionally based on the already qualified x16j-fix1+x16k+x16l state.
grep -q 'q2Root=x16m-bisection-1e-8cell' "$SRC" && {
  echo "[0493x16m] patch already applied; validating"
  bash "$CHECK"
  exit 0
}
grep -q '0493x16l-penetration' "$SRC" || {
  echo "[0493x16m] ERROR x16l prerequisite not found" >&2; exit 3; }
grep -q 'chiKineticBoundary0493x16j' "$SRC" || {
  echo "[0493x16m] ERROR x16j prerequisite not found" >&2; exit 3; }
grep -q 'targetPathCells0493x16m' "$SRC" && {
  echo "[0493x16m] ERROR partial x16m state detected" >&2; exit 4; }

patch --dry-run -p1 < "$PATCH"
patch -p1 < "$PATCH"
bash "$CHECK"
echo "[0493x16m] APPLY PASS"
