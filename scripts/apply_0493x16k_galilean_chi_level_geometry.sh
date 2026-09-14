#!/usr/bin/env bash
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT" || exit $?
PATCH="patches/0493x16k_galilean_chi_level_geometry.patch"
SRC="src/cuda_chi_solid_0493x16e.cu"
MARKER="kineticLevelHalfWidth0493x16k"

if grep -q "$MARKER" "$SRC"; then
  echo "[0493x16k] already applied; validating"
  bash scripts/check_0493x16k_galilean_chi_level_geometry.sh
  exit $?
fi

# x16k is a correction on top of x16j-fix1.  Refuse the old post-Q6/local
# dispatch because that timing defect would invalidate the geometry test.
grep -Fq 'cuda_q6_apply_chi_kinetic_boundary_prestream_0493x16j' src/src_mpcd_base.cpp || {
  echo "[0493x16k] ERROR prerequisite 0493x16j-fix1 prestream dispatch is absent" >&2
  exit 2
}

for need in \
  'continuousChiGeometry0493x16j' \
  'solidFraction' \
  'const double sd = fabs(d) - half;' \
  'static_cast<float>(1.0 - solidFraction)'; do
  grep -Fq "$need" "$SRC" || {
    echo "[0493x16k] ERROR prerequisite missing: $need" >&2
    exit 2
  }
done

patch -p1 --dry-run < "$PATCH" || exit $?
patch -p1 < "$PATCH" || exit $?

echo "[0493x16k] apply PASS"
