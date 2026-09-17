#!/usr/bin/env bash
# 0493x19b-fix3 — complete operator-by-operator angular-momentum audit.
# Diagnostic only.  Physics is unchanged.  One established bounceback state is
# restarted for a short run.  Global mass/P/L/K/I moments are sampled at every
# mutating stage of the actual solver step.  Reduced livevis_record fields are
# written on every step for an independent consecutive field-level inspection.

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT" || exit 2

SOURCE_OUTPUT="${SOURCE_OUTPUT:-runs/0493x19b_fix2_angular_balance/bounceback/fresh/output}"
if [[ ! -d "$SOURCE_OUTPUT" ]]; then
  SOURCE_OUTPUT="runs/0493x19b_fix1_torque_split/bounceback/fresh/output"
fi
if [[ ! -d "$SOURCE_OUTPUT" ]]; then
  SOURCE_OUTPUT="runs/0493x19b_prescribed_rotating_annulus_pair/bounceback/fresh/output"
fi
DIAG_BASE_RUN_ROOT="${DIAG_BASE_RUN_ROOT:-runs/0493x19b_fix3_full_angular_audit/bounceback}"
DIAG_STEPS="${DIAG_STEPS:-400}"

if [[ ! -d "$SOURCE_OUTPUT" ]]; then
  echo "[0493x19b-fix3] ERROR source output directory not found: $SOURCE_OUTPUT" >&2
  exit 2
fi
LATEST_STATE="$(find "$SOURCE_OUTPUT" -maxdepth 1 -type f -name 'state_step_*.smpcd' -print | sort -V | tail -n 1)"
if [[ -z "$LATEST_STATE" || ! -s "$LATEST_STATE" ]]; then
  echo "[0493x19b-fix3] ERROR no restart dump state_step_*.smpcd found in $SOURCE_OUTPUT" >&2
  exit 2
fi
base="$(basename "$LATEST_STATE")"
SOURCE_STEP="$(printf '%s\n' "$base" | sed -n 's/^state_step_0*\([0-9][0-9]*\)\.smpcd$/\1/p')"
if [[ -z "$SOURCE_STEP" ]]; then
  echo "[0493x19b-fix3] ERROR cannot parse restart step from $base" >&2
  exit 2
fi

printf '\n===== 0493x19b-fix3 FULL ANGULAR AUDIT =====\n'
printf 'source=%s\n' "$LATEST_STATE"
printf 'sourceStep=%s additionalSteps=%s\n' "$SOURCE_STEP" "$DIAG_STEPS"
printf 'newRunRoot=%s/fresh\n' "$DIAG_BASE_RUN_ROOT"
printf 'operator stages: prestream / wall / stream / boundary / immersed / SRC / Q6 / capacity / thermostat / mean / Darcy / resampling guards / end\n'
printf 'reduced consecutive recording: rho,ux,uy on 48x48 every step\n'
printf 'Only bounceback is rerun; no specular rerun.\n'
printf '================================================\n\n'

export MPCD_X19B_FIX3_FULL_ANGULAR_AUDIT=1
export MPCD_X19B_FIX2_SRC_ANGULAR_AUDIT=0

ROOT="$ROOT" \
KINETIC_MODE=bounceback \
CASE_LABEL=0493x19b_fix3_bounceback_full_angular_audit \
BASE_RUN_ROOT="$DIAG_BASE_RUN_ROOT" \
STEPS="$DIAG_STEPS" \
RESTART_STATE="$LATEST_STATE" \
RESTART_FROM_STEP="$SOURCE_STEP" \
CLEAN_RUN_ROOT=1 \
SUMMARY_EVERY=1 \
DUMP_STATE_EVERY="$DIAG_STEPS" \
LIVE_PROGRESS=1 \
LIVE_VIS_ENABLE=1 \
LIVE_VIS_EVERY=10 \
LIVE_VIS_NX=48 \
LIVE_VIS_NY=48 \
FILTERED_RECORDING_ENABLE=1 \
RECORD_ENABLE=true \
RECORD_EVERY=1 \
RECORD_FIELDS=rho,ux,uy \
bash "$ROOT/scripts/run_0493x19b_prescribed_rotating_annulus.sh" || exit $?

OUT="$ROOT/$DIAG_BASE_RUN_ROOT/fresh/output"
STAGECSV="$OUT/angular_balance_stages_0493x19b_fix3.csv"
WALLCSV="$OUT/chi_kinetic_boundary_0493x16j.csv"
[[ -s "$STAGECSV" ]] || { echo "[0493x19b-fix3] ERROR missing $STAGECSV" >&2; exit 2; }
[[ -s "$WALLCSV" ]] || { echo "[0493x19b-fix3] ERROR missing $WALLCSV" >&2; exit 2; }

stage_header="$(head -n 1 "$STAGECSV")"
for c in stage angularMomentumZ mass momentumX momentumY kineticEnergy polarMassMoment radialMomentum tangentialMomentum; do
  printf '%s\n' "$stage_header" | grep -q "$c" || {
    echo "[0493x19b-fix3] ERROR missing stage diagnostic column $c" >&2
    exit 2
  }
done
for stage in step_start post_prestream_sources post_chi_wall post_stream post_boundary post_immersed post_penetration_diagnostic post_src_collision post_q6_projection post_closed_capacity post_thermostat post_keep_mean_flow post_darcy post_solid_dynamics post_mass_recondition post_population_guard step_end; do
  grep -q ",\"$stage\"," "$STAGECSV" || {
    echo "[0493x19b-fix3] ERROR missing stage $stage" >&2
    exit 2
  }
done
wall_header="$(head -n 1 "$WALLCSV")"
for c in x19bInnerTorqueImpulse x19bOuterTorqueImpulse x19bInnerTorqueTangentialImpulse x19bOuterTorqueTangentialImpulse; do
  printf '%s\n' "$wall_header" | grep -q "$c" || {
    echo "[0493x19b-fix3] ERROR missing wall diagnostic column $c" >&2
    exit 2
  }
done

stage_rows="$(awk 'END{print NR-1}' "$STAGECSV")"
wall_rows="$(awk 'END{print NR-1}' "$WALLCSV")"
printf '[0493x19b-fix3] rows stage=%s wall=%s\n' "$stage_rows" "$wall_rows"
if [[ "$stage_rows" -lt $((DIAG_STEPS*16)) || "$wall_rows" -lt $((DIAG_STEPS-5)) ]]; then
  echo "[0493x19b-fix3] ERROR incomplete every-step diagnostic coverage" >&2
  exit 2
fi

echo "[0493x19b-fix3] COMPLETE output=$OUT"
echo "[0493x19b-fix3] MATLAB: cd matlab; results = analyze_0493x19b_fix3_full_angular_audit;"
