#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-/mnt/e/SRC_MPCD_DEV/SRC_GPU-SURF}"
cd "$ROOT"

RUNNER="${RUNNER:-scripts/run_0493x23e_article_couette_livevis.sh}"
SRC_RUN="${SRC_RUN:-runs/0493x23e_article_couette_livevis_Uw0075_seed593170}"
TARGET_STEP="${TARGET_STEP:-30000}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-1000}"
SUMMARY_EVERY="${SUMMARY_EVERY:-1000}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"

[[ -f "$RUNNER" ]] || { echo "ERROR: runner introuvable: $RUNNER" >&2; exit 2; }
[[ -d "$SRC_RUN/output" ]] || { echo "ERROR: output source introuvable: $SRC_RUN/output" >&2; exit 2; }

STATE="${RESTART_STATE:-$SRC_RUN/output/state_step_00018000.smpcd}"
if [[ ! -f "$STATE" ]]; then
  STATE="$(find "$SRC_RUN/output" -maxdepth 1 -type f -name 'state_step_*.smpcd' | sort | tail -1)"
fi
[[ -n "$STATE" && -f "$STATE" ]] || { echo "ERROR: aucun checkpoint state_step_*.smpcd" >&2; exit 2; }

base="$(basename "$STATE")"
if [[ "$base" =~ ^state_step_0*([0-9]+)\.smpcd$ ]]; then
  FROM_STEP=$((10#${BASH_REMATCH[1]}))
else
  echo "ERROR: impossible de deduire le step depuis $base" >&2
  exit 2
fi
(( TARGET_STEP > FROM_STEP )) || { echo "ERROR: TARGET_STEP=$TARGET_STEP <= FROM_STEP=$FROM_STEP" >&2; exit 2; }
ADDITIONAL_STEPS=$((TARGET_STEP-FROM_STEP))

CONT_RUN="${CONT_RUN:-runs/0493x23e_article_couette_livevis_Uw0075_seed593170_restart_${FROM_STEP}_to_${TARGET_STEP}}"

printf '[x23e-restart] runner      = %s\n' "$RUNNER"
printf '[x23e-restart] checkpoint  = %s\n' "$STATE"
printf '[x23e-restart] global step = %d -> %d (%d additional)\n' "$FROM_STEP" "$TARGET_STEP" "$ADDITIONAL_STEPS"
printf '[x23e-restart] output      = %s\n' "$CONT_RUN"
printf '[x23e-restart] dumps       = every %d steps\n' "$DUMP_STATE_EVERY"

# Support the two restart conventions used by SRC_GPU-SURF runners.
if grep -qE '(^|[^A-Za-z0-9_])RESTART_STATE([^A-Za-z0-9_]|$)' "$RUNNER"; then
  echo '[x23e-restart] detected convention: RESTART_STATE + STEPS'
  exec env \
    RESTART=1 \
    RESTART_STATE="$STATE" \
    RESTART_FROM_STEP="$FROM_STEP" \
    RESTART_TAG="from${FROM_STEP}_to${TARGET_STEP}" \
    RUN_ROOT="$CONT_RUN" \
    STEPS="$ADDITIONAL_STEPS" \
    DUMP_STATE_EVERY="$DUMP_STATE_EVERY" \
    SUMMARY_EVERY="$SUMMARY_EVERY" \
    LIVE_PROGRESS="$LIVE_PROGRESS" \
    bash "$RUNNER"
fi

if grep -qE '(^|[^A-Za-z0-9_])TARGET_STEP([^A-Za-z0-9_]|$)' "$RUNNER" && \
   grep -qE '(^|[^A-Za-z0-9_])RESTART([^A-Za-z0-9_]|$)' "$RUNNER"; then
  echo '[x23e-restart] detected convention: RESTART=<state> + TARGET_STEP'
  exec env \
    RESTART="$STATE" \
    TARGET_STEP="$TARGET_STEP" \
    RUN_ROOT="$CONT_RUN" \
    DUMP_STATE_EVERY="$DUMP_STATE_EVERY" \
    SUMMARY_EVERY="$SUMMARY_EVERY" \
    LIVE_PROGRESS="$LIVE_PROGRESS" \
    bash "$RUNNER"
fi

echo 'ERROR: le runner x23e ne declare pas une interface restart reconnue.' >&2
echo 'Lignes pertinentes du runner :' >&2
grep -nE 'RESTART|initialState|initial.*state|state_step|STEPS|RUN_ROOT' "$RUNNER" | head -120 >&2 || true
exit 3
