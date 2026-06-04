#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

RUN_ROOT="${1:-runs/openmp_production_stripped_smoke_0184}"

status=0

echo "[0184-audit] C++ runtime forbidden-token audit"
if grep -RInE 'MPCD_INTERNAL_PROFILES|getenv\(|phase_profile_[^/]*\.csv|q6_cg_profile_[^/]*\.csv|deposit_profile_[^/]*\.csv|resampling_guard_profile_[^/]*\.csv|post_guard_profile_[^/]*\.csv|post_guard_equivalence[^/]*\.csv' src include; then
  echo "[0184-audit] ERROR: forbidden runtime profile token found in src/include" >&2
  status=1
else
  echo "[0184-audit] PASS: no forbidden runtime profile token in src/include"
fi

echo "[0184-audit] generated internal-file audit under: $RUN_ROOT"
if [[ -d "$RUN_ROOT" ]]; then
  if find "$RUN_ROOT" \
    \( -name 'phase_profile_*.csv' \
    -o -name 'q6_cg_profile_*.csv' \
    -o -name 'deposit_profile_*.csv' \
    -o -name 'resampling_guard_profile_*.csv' \
    -o -name 'post_guard_profile_*.csv' \
    -o -name 'post_guard_equivalence*.csv' \
    -o -name 'post_guard_equivalence_trace_*.csv' \) \
    -type f -print | grep -q .; then
    echo "[0184-audit] ERROR: generated internal profile files found" >&2
    find "$RUN_ROOT" \
      \( -name 'phase_profile_*.csv' \
      -o -name 'q6_cg_profile_*.csv' \
      -o -name 'deposit_profile_*.csv' \
      -o -name 'resampling_guard_profile_*.csv' \
      -o -name 'post_guard_profile_*.csv' \
      -o -name 'post_guard_equivalence*.csv' \
      -o -name 'post_guard_equivalence_trace_*.csv' \) \
      -type f -print >&2
    status=1
  else
    echo "[0184-audit] PASS: no generated internal profile files"
  fi
else
  echo "[0184-audit] WARN: run root does not exist yet: $RUN_ROOT"
fi

exit "$status"
