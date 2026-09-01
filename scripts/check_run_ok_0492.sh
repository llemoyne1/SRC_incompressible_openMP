#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

common="scripts/src_mpcd_run_ok_common.sh"
livevis="./livevis_control.kv"
expected_bin='build/src_mpcd_base_cuda_q6_resident_livevis_0486'

[[ -f "$common" ]] || { echo "[run-ok-check] missing common base: $common" >&2; exit 1; }
[[ -f "$livevis" ]] || { echo "[run-ok-check] missing root LiveVis control: $livevis" >&2; exit 1; }
bash -n "$common"

count=0
for f in scripts/run_ok_*.sh; do
  [[ -f "$f" ]] || continue
  count=$((count+1))
  bash -n "$f"
  grep -Fq 'source "$ROOT/scripts/src_mpcd_run_ok_common.sh"' "$f" || {
    echo "[run-ok-check] runner does not source the unique common base: $f" >&2; exit 1;
  }
  nsource=$(grep -Ec '^[[:space:]]*(source|\.)[[:space:]]+' "$f" || true)
  [[ "$nsource" == 1 ]] || {
    echo "[run-ok-check] runner has $nsource shell source dependencies, expected exactly 1: $f" >&2; exit 1;
  }
  if grep -Eq '^[[:space:]]*(exec[[:space:]]+)?bash[[:space:]]+.*scripts/' "$f"; then
    echo "[run-ok-check] runner chains to another shell runner: $f" >&2; exit 1
  fi
  grep -Fq "$expected_bin" "$f" || { echo "[run-ok-check] missing default 0486 binary: $f" >&2; exit 1; }
  grep -Fq 'PREFLIGHT_ONLY=' "$f" || { echo "[run-ok-check] missing PREFLIGHT_ONLY: $f" >&2; exit 1; }
done

for token in \
  'LIVE_VIS_CONTROL_FILE="$ROOT/livevis_control.kv"' \
  'OVERWRITE_LIVEVIS_CONTROL=0' \
  'suite_print_effective_run_0493x13zi' \
  'FLUID: domain=' \
  'LIVE:  grid=' \
  'run_ok_surface_export_qualified_liquid_vacuum_flags_0493x13zi'; do
  grep -Fq "$token" "$common" || { echo "[run-ok-check] common contract missing: $token" >&2; exit 1; }
done

for spec in \
  'scripts/run_ok_dambreak.sh|SURFACE_TENSION_SIGMA="${SURFACE_TENSION_SIGMA:-945.0}"|PHASE_INTERFACE_B_SELECTOR="${PHASE_INTERFACE_B_SELECTOR:-vacuum}"' \
  'scripts/run_ok_injection_type1_into_type2_empty.sh|SURFACE_TENSION_SIGMA="${SURFACE_TENSION_SIGMA:-945.0}"|PHASE_INTERFACE_KINETIC_REFLECTION_FRACTION="${PHASE_INTERFACE_KINETIC_REFLECTION_FRACTION:-1.0}"' \
  'scripts/run_ok_injection_type1_into_type2.sh|SURFACE_TENSION_SIGMA="${SURFACE_TENSION_SIGMA:-945.0}"|PHASE_INTERFACE_KINETIC_REFLECTION_FRACTION="${PHASE_INTERFACE_KINETIC_REFLECTION_FRACTION:-0.0}"' \
  'scripts/run_ok_splash.sh|SIGMA_ACTIVE="${SIGMA_ACTIVE:-945.0}"|SURFACE_TENSION_MIN_RADIUS_CELLS="${SURFACE_TENSION_MIN_RADIUS_CELLS:-4}"' \
  'scripts/run_ok_puddle.sh|SIGMA_ACTIVE="${SIGMA_ACTIVE:-945.0}"|SURFACE_TENSION_MIN_RADIUS_CELLS="${SURFACE_TENSION_MIN_RADIUS_CELLS:-4}"' \
  'scripts/run_ok_dripping.sh|SIGMA_ACTIVE="${SIGMA_ACTIVE:-2500.0}"|SURFACE_TENSION_MIN_RADIUS_CELLS="${SURFACE_TENSION_MIN_RADIUS_CELLS:-3}"'; do
  IFS='|' read -r f a b <<< "$spec"
  grep -Fq "$a" "$f" || { echo "[run-ok-check] visible physics parameter missing: $f :: $a" >&2; exit 1; }
  grep -Fq "$b" "$f" || { echo "[run-ok-check] visible physics parameter missing: $f :: $b" >&2; exit 1; }
done

# 0493x13zj: every public runner exposes the reference-fluid microphysics directly.
for f in scripts/run_ok_*.sh; do
  grep -Fq 'GAMMA="${GAMMA:-8}"' "$f" || { echo "[run-ok-check] G08 gamma missing: $f" >&2; exit 1; }
  grep -Fq '0.0063471328149122585' "$f" || { echo "[run-ok-check] G08 dt missing: $f" >&2; exit 1; }
  grep -Fq 'KBT="${KBT:-0.125}"' "$f" || { echo "[run-ok-check] G08 kBT missing: $f" >&2; exit 1; }
  grep -Fq '2.0943951023931953' "$f" || { echo "[run-ok-check] 120deg rotation missing: $f" >&2; exit 1; }
done
for tok in 'liveEvery = 100' 'recordEnable = true' 'recordFields = mass,ux,uy' 'recordEvery = 100' 'filterSampleEvery = 100'; do
  grep -Fq "$tok" "$livevis" || { echo "[run-ok-check] LiveVis default missing: $tok" >&2; exit 1; }
done
if grep -Eq '^[[:space:]]*liveGridN[xy][[:space:]]*=' "$livevis"; then
  echo '[run-ok-check] root livevis must not hard-code liveGridNx/liveGridNy; inherit solver Nx/Ny' >&2; exit 1
fi

# Keep the resident-species helper sanity checks from the historical checker.
source "$common"
SPECIES_RESAMPLING_ENABLE=true
[[ "$(suite_species_resident_mode_0492a src-q6-resampling periodic)" == production ]] || { echo '[run-ok-check] periodic auto mode is not production' >&2; exit 1; }
[[ "$(suite_species_resident_mode_0492a src-q6-resampling segmented)" == production ]] || { echo '[run-ok-check] segmented auto mode is not production' >&2; exit 1; }
SPECIES_RESIDENT_MODE=validation
[[ "$(suite_species_resident_mode_0492a src-q6-resampling segmented)" == validation ]] || { echo '[run-ok-check] explicit validation mode failed' >&2; exit 1; }
unset SPECIES_RESIDENT_MODE SPECIES_RESAMPLING_ENABLE

echo "[run-ok-check] PASS runners=$count common=$common livevis=$livevis"
