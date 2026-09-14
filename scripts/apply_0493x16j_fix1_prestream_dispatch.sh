#!/usr/bin/env bash
# Apply 0493x16j-fix1 from repository root.
ROOT="${ROOT:-$(pwd)}"
cd "$ROOT" || exit $?
PATCH="patches/0493x16j_fix1_prestream_dispatch.patch"

if [[ ! -f "$PATCH" ]]; then
  echo "[0493x16j-fix1] ERROR missing $PATCH" >&2
  exit 2
fi

# Idempotent validation.
if grep -q '0493x16j-fix1: x10n interprets particle x/y as PRE-STREAM' src/src_mpcd_base.cpp 2>/dev/null; then
  grep -q 'cuda_q6_apply_chi_kinetic_boundary_prestream_0493x16j' include/cuda_q6_resident_0400.h || exit 2
  grep -q '0493x16j_prestream_chi_kinetic_boundary' src/cuda_q6_resident_0400.cu || exit 2
  grep -q 'timing=prestream geometry=S=1-chi' src/cuda_q6_resident_0400.cu || exit 2
  echo "[0493x16j-fix1] already applied; validation PASS"
  exit 0
fi

# Exact x16j prerequisites from the inspected 130926 worktree.
for token in \
  'chiKineticBoundaryMode = "off"' \
  'apply_chi_kinetic_boundary_0493x16j(' \
  'q6_x10n_apply_continuous_moving_interface(' \
  'cuda_q6_chi_kinetic_wall_reaction_device_0493x16j(' \
  '0493x16j missing resident chi kinetic wall-reaction field'
do
  if ! grep -RqsF "$token" include src; then
    echo "[0493x16j-fix1] ERROR prerequisite not found: $token" >&2
    exit 2
  fi
done

patch --dry-run -p1 < "$PATCH" || {
  echo "[0493x16j-fix1] ERROR patch dry-run failed; tree differs from inspected x16j state" >&2
  exit 2
}
patch -p1 < "$PATCH" || exit $?

bash -n scripts/run_0493x16j_chi_kinetic_specular_case.sh || exit $?
bash -n scripts/run_0493x16j_fix1_prestream_smoke.sh || exit $?

grep -q '0493x16j-fix1: x10n interprets particle x/y as PRE-STREAM' src/src_mpcd_base.cpp || exit 2
grep -q 'timing=prestream geometry=S=1-chi' src/cuda_q6_resident_0400.cu || exit 2
if grep -n -A18 'apply_independent_masked_species_q6_0493w5' src/cuda_q6_resident_0400.cu | grep -q 'apply_chi_kinetic_boundary_0493x16j'; then
  echo "[0493x16j-fix1] ERROR stale species-mode-local x16j dispatch remains" >&2
  exit 2
fi

echo "[0493x16j-fix1] apply PASS"
