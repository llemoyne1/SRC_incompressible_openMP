#!/usr/bin/env bash
# 0493x19b-fix1 — short restart-only torque decomposition diagnostic.
# No physics is changed. The script restarts ONLY the established bounceback
# annulus from its latest available dump and runs a short diagnostic extension.

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT" || exit 2

SOURCE_OUTPUT="${SOURCE_OUTPUT:-runs/0493x19b_prescribed_rotating_annulus_pair/bounceback/fresh/output}"
DIAG_BASE_RUN_ROOT="${DIAG_BASE_RUN_ROOT:-runs/0493x19b_fix1_torque_split/bounceback}"
DIAG_STEPS="${DIAG_STEPS:-3000}"

if [[ ! -d "$SOURCE_OUTPUT" ]]; then
  echo "[0493x19b-fix1] ERROR source output directory not found: $SOURCE_OUTPUT" >&2
  exit 2
fi

LATEST_STATE="$(find "$SOURCE_OUTPUT" -maxdepth 1 -type f -name 'state_step_*.smpcd' -print | LC_ALL=C sort | tail -n 1)"
if [[ -z "$LATEST_STATE" || ! -s "$LATEST_STATE" ]]; then
  echo "[0493x19b-fix1] ERROR no restart dump state_step_*.smpcd found in $SOURCE_OUTPUT" >&2
  exit 2
fi

base="$(basename "$LATEST_STATE")"
SOURCE_STEP="$(printf '%s\n' "$base" | sed -n 's/^state_step_0*\([0-9][0-9]*\)\.smpcd$/\1/p')"
if [[ -z "$SOURCE_STEP" ]]; then
  echo "[0493x19b-fix1] ERROR cannot parse restart step from $base" >&2
  exit 2
fi

printf '\n===== 0493x19b-fix1 SHORT TORQUE-SPLIT RESTART =====\n'
printf 'source=%s\n' "$LATEST_STATE"
printf 'sourceStep=%s additionalSteps=%s\n' "$SOURCE_STEP" "$DIAG_STEPS"
printf 'newRunRoot=%s/fresh\n' "$DIAG_BASE_RUN_ROOT"
printf 'Only bounceback is rerun; no specular rerun.\n'
printf '====================================================\n\n'

ROOT="$ROOT" \
KINETIC_MODE=bounceback \
CASE_LABEL=0493x19b_fix1_bounceback_torque_split \
BASE_RUN_ROOT="$DIAG_BASE_RUN_ROOT" \
STEPS="$DIAG_STEPS" \
RESTART_STATE="$LATEST_STATE" \
RESTART_FROM_STEP="$SOURCE_STEP" \
CLEAN_RUN_ROOT=1 \
SUMMARY_EVERY=10 \
DUMP_STATE_EVERY=1000 \
LIVE_PROGRESS=1 \
LIVE_VIS_ENABLE=1 \
LIVE_VIS_EVERY=1 \
LIVE_VIS_NX=64 \
LIVE_VIS_NY=64 \
FILTERED_RECORDING_ENABLE=1 \
RECORD_ENABLE=true \
RECORD_EVERY=100 \
RECORD_FIELDS=rho,ux,uy \
bash "$ROOT/scripts/run_0493x19b_prescribed_rotating_annulus.sh" || exit $?

OUT="$ROOT/$DIAG_BASE_RUN_ROOT/fresh/output"
CSV="$OUT/chi_kinetic_boundary_0493x16j.csv"
[[ -s "$CSV" ]] || { echo "[0493x19b-fix1] ERROR missing $CSV" >&2; exit 2; }
header="$(head -n 1 "$CSV")"
for c in x19bInnerTorqueNormalImpulse x19bInnerTorqueTangentialImpulse x19bOuterTorqueNormalImpulse x19bOuterTorqueTangentialImpulse; do
  printf '%s\n' "$header" | grep -q "$c" || {
    echo "[0493x19b-fix1] ERROR missing diagnostic column $c" >&2
    exit 2
  }
done

echo "[0493x19b-fix1] COMPLETE output=$OUT"
echo "[0493x19b-fix1] MATLAB: cd matlab; results = analyze_0493x19b_fix1_torque_split;"
