#!/usr/bin/env bash
# Apply 0493x16l from repository root. Idempotent by marker validation.
ROOT="${ROOT:-$(pwd)}"
cd "$ROOT" || exit $?
PATCH="patches/0493x16l_direct_chi_penetration.patch"

[[ -f "$PATCH" ]] || { echo "[0493x16l] ERROR missing $PATCH (extract ZIP at repository root)" >&2; exit 2; }
[[ -f src/cuda_q6_resident_0400.cu ]] || { echo "[0493x16l] ERROR run from repository root" >&2; exit 2; }

grep -q '0493x16j-fix1: the chi wall pass now runs before ordinary streaming' src/cuda_q6_resident_0400.cu || {
  echo "[0493x16l] ERROR prerequisite x16j-fix1 prestream dispatch not found" >&2; exit 2; }
grep -q '0493x16k: a moving material wall must be reconstructed from a level' src/cuda_chi_solid_0493x16e.cu || {
  echo "[0493x16l] ERROR prerequisite x16k Galilean level geometry not found" >&2; exit 2; }

if grep -q 'cuda_q6_record_chi_penetration_poststream_0493x16l' src/cuda_q6_resident_0400.cu; then
  echo "[0493x16l] already applied; validating"
  bash scripts/check_0493x16l_direct_chi_penetration.sh
  exit $?
fi

patch --dry-run -p1 < "$PATCH" || {
  echo "[0493x16l] ERROR patch dry-run failed; tree differs from qualified x16k state" >&2
  exit 2
}
patch -p1 < "$PATCH" || exit $?

echo "[0493x16l] patch applied"
bash scripts/check_0493x16l_direct_chi_penetration.sh
