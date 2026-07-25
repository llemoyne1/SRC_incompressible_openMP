#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

HELPER="scripts/src_mpcd_run_common_0434.sh"
RUNNER="scripts/run_ok_injection_type1_into_type2_empty.sh"

bash -n "$HELPER"
bash -n "$RUNNER"

grep -q 'suite_species_resident_mode_0493a' "$HELPER"
grep -q "printf 'production'" "$HELPER"

! grep -q 'fast requires topology=periodic' "$HELPER"
! grep -q 'fast species resident path is restricted to topology=periodic' "$HELPER"
! grep -q 'SPECIES_RESIDENT_MODE=fast requires topology=periodic' "$HELPER"

grep -q 'MPCD_CUDA_RESAMPLING_CPU_OP_CARRIER_0458=0' "$HELPER"
grep -q 'RESAMPLING_HOST_PATCHBACK_ENABLE:-0' "$HELPER"
grep -q 'RESAMPLING_SPARSE_DEVICE_GATE_ENABLE:-0' "$HELPER"

grep -q 'SPECIES_RESIDENT_MODE="${SPECIES_RESIDENT_MODE:-production}"' "$RUNNER"
grep -q 'SPECIES_DIAGNOSTICS_ENABLE="${SPECIES_DIAGNOSTICS_ENABLE:-false}"' "$RUNNER"

if grep -Rqs \
  '0490m resident fast path is currently restricted to fully periodic boundaries' \
  src include; then
  echo "[0493a-check] ERROR C++ topology guard still present" >&2
  exit 2
fi

# Q6 and Darcy source files must not be modified by this patch.
changed="$(git diff --name-only)"
if grep -Eq \
  '(^|/)(cuda_q6|cuda_species_q6|darcy|topo_).*' \
  <<<"$changed"; then
  echo "[0493a-check] ERROR Q6/Darcy implementation file modified unexpectedly" >&2
  grep -E '(^|/)(cuda_q6|cuda_species_q6|darcy|topo_).*' <<<"$changed" >&2
  exit 2
fi

echo "[0493a-check] PASS"
echo "[0493a-check] universal_resident_routing=on"
echo "[0493a-check] cpu_op_carrier=off"
echo "[0493a-check] host_patchback=off"
echo "[0493a-check] q6_physics_untouched=1"
echo "[0493a-check] darcy_physics_untouched=1"
