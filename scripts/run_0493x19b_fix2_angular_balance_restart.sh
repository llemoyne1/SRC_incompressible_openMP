#!/usr/bin/env bash
# 0493x19b-fix2 — short every-step wall/SRC angular-momentum audit.
# Diagnostic-only: physics is unchanged.  Restart established bounceback flow,
# sample every wall collision, and measure the real-fluid delta-L produced by
# the bulk SRC rotation itself.

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT" || exit 2

# Prefer the already-extended fix1 state.  Fall back to the original x19b
# bounceback production only when fix1 is not present.
SOURCE_OUTPUT="${SOURCE_OUTPUT:-runs/0493x19b_fix1_torque_split/bounceback/fresh/output}"
if [[ ! -d "$SOURCE_OUTPUT" ]]; then
  SOURCE_OUTPUT="runs/0493x19b_prescribed_rotating_annulus_pair/bounceback/fresh/output"
fi
DIAG_BASE_RUN_ROOT="${DIAG_BASE_RUN_ROOT:-runs/0493x19b_fix2_angular_balance/bounceback}"
DIAG_STEPS="${DIAG_STEPS:-1500}"

if [[ ! -d "$SOURCE_OUTPUT" ]]; then
  echo "[0493x19b-fix2] ERROR source output directory not found: $SOURCE_OUTPUT" >&2
  exit 2
fi

LATEST_STATE="$(find "$SOURCE_OUTPUT" -maxdepth 1 -type f -name 'state_step_*.smpcd' -print | sort -V | tail -n 1)"
if [[ -z "$LATEST_STATE" || ! -s "$LATEST_STATE" ]]; then
  echo "[0493x19b-fix2] ERROR no restart dump state_step_*.smpcd found in $SOURCE_OUTPUT" >&2
  exit 2
fi
base="$(basename "$LATEST_STATE")"
SOURCE_STEP="$(printf '%s\n' "$base" | sed -n 's/^state_step_0*\([0-9][0-9]*\)\.smpcd$/\1/p')"
if [[ -z "$SOURCE_STEP" ]]; then
  echo "[0493x19b-fix2] ERROR cannot parse restart step from $base" >&2
  exit 2
fi

printf '\n===== 0493x19b-fix2 ANGULAR-BALANCE RESTART =====\n'
printf 'source=%s\n' "$LATEST_STATE"
printf 'sourceStep=%s additionalSteps=%s\n' "$SOURCE_STEP" "$DIAG_STEPS"
printf 'newRunRoot=%s/fresh\n' "$DIAG_BASE_RUN_ROOT"
printf 'wall torque sampled every step; SRC delta-L audit enabled\n'
printf 'Only bounceback is rerun; no specular rerun.\n'
printf '===================================================\n\n'

export MPCD_X19B_FIX2_SRC_ANGULAR_AUDIT=1

ROOT="$ROOT" \
KINETIC_MODE=bounceback \
CASE_LABEL=0493x19b_fix2_bounceback_angular_balance \
BASE_RUN_ROOT="$DIAG_BASE_RUN_ROOT" \
STEPS="$DIAG_STEPS" \
RESTART_STATE="$LATEST_STATE" \
RESTART_FROM_STEP="$SOURCE_STEP" \
CLEAN_RUN_ROOT=1 \
SUMMARY_EVERY=1 \
DUMP_STATE_EVERY=1000 \
LIVE_PROGRESS=1 \
LIVE_VIS_ENABLE=1 \
LIVE_VIS_EVERY=10 \
LIVE_VIS_NX=64 \
LIVE_VIS_NY=64 \
FILTERED_RECORDING_ENABLE=1 \
RECORD_ENABLE=true \
RECORD_EVERY=100 \
RECORD_FIELDS=rho,ux,uy \
bash "$ROOT/scripts/run_0493x19b_prescribed_rotating_annulus.sh" || exit $?

OUT="$ROOT/$DIAG_BASE_RUN_ROOT/fresh/output"
WALLCSV="$OUT/chi_kinetic_boundary_0493x16j.csv"
SRCCSV="$OUT/src_angular_momentum_0493x19b_fix2.csv"
[[ -s "$WALLCSV" ]] || { echo "[0493x19b-fix2] ERROR missing $WALLCSV" >&2; exit 2; }
[[ -s "$SRCCSV" ]] || { echo "[0493x19b-fix2] ERROR missing $SRCCSV" >&2; exit 2; }

wall_header="$(head -n 1 "$WALLCSV")"
for c in x19bInnerTorqueNormalImpulse x19bInnerTorqueTangentialImpulse x19bOuterTorqueNormalImpulse x19bOuterTorqueTangentialImpulse; do
  printf '%s\n' "$wall_header" | grep -q "$c" || {
    echo "[0493x19b-fix2] ERROR missing wall diagnostic column $c" >&2
    exit 2
  }
done
src_header="$(head -n 1 "$SRCCSV")"
for c in LbeforeSrc LafterSrc deltaLSrc; do
  printf '%s\n' "$src_header" | grep -q "$c" || {
    echo "[0493x19b-fix2] ERROR missing SRC angular diagnostic column $c" >&2
    exit 2
  }
done

wall_rows="$(awk 'END{print NR-1}' "$WALLCSV")"
src_rows="$(awk 'END{print NR-1}' "$SRCCSV")"
printf '[0493x19b-fix2] rows wall=%s src=%s\n' "$wall_rows" "$src_rows"
if [[ "$wall_rows" -lt $((DIAG_STEPS-5)) || "$src_rows" -lt $((DIAG_STEPS-5)) ]]; then
  echo "[0493x19b-fix2] ERROR expected approximately one diagnostic row per solver step" >&2
  exit 2
fi

echo "[0493x19b-fix2] COMPLETE output=$OUT"
echo "[0493x19b-fix2] MATLAB: cd matlab; results = analyze_0493x19b_fix2_angular_balance;"
