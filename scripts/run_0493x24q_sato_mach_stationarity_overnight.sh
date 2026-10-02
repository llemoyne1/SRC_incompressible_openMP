#!/usr/bin/env bash
# =============================================================================
# 0493x24q — Sato H/D=0.8 gas-compressibility / Mach stationarity campaign
#
# Purpose
#   Compare the liquid-cavity response at four gas thermal-Mach proxies while
#   keeping the Sato momentum/capillary/gravity similarity controls unchanged:
#
#       rhoG/rhoL, Ujet, Fr_m, We_g(D), Bo_l(D), H/D, geometry
#
#   Only gas kBT/m and dt are changed.  Each case is first thermally relaxed
#   without directed injection for the same physical duration, then forced for
#   a long matched physical duration.
#
# Important
#   - Runner-only campaign: NO C++/CUDA modification.
#   - ./livevis_control.kv remains user-owned/read-only.
#   - Cases run SEQUENTIALLY: one operation at a time.
#   - The current qualified segmented topology remains OUTLET_MODE=hybrid.
#   - Long duration tests whether a stationary liquid response exists; it does
#     not assume that the global gas inventory is stationary.
#
# Existing runners required:
#   scripts/run_0493x24h_sato_short_nozzle_relax.sh
#   scripts/run_0493x24i_sato_short_nozzle_forced.sh
#
# Common starting state required:
#   runs/0493x24h_sato_short_nozzle_relax_seed493205/
#     restart_short_nozzle_relax/output/state_step_00002000.smpcd
#
# Default physical durations:
#   T_RELAX  = 0.4
#   T_FORCED = 6.0
#
# Approximate thermal Mach proxy:
#   Ma_T = Ujet / sqrt(kBT_g/m_g)
#
# Cases:
#   M067 : kBT/m=0.8   dt=4e-4  Ma_T~6.67
#   M033 : kBT/m=3.2   dt=4e-4  Ma_T~3.34
#   M017 : kBT/m=12.8  dt=2e-4  Ma_T~1.67
#   M008 : kBT/m=51.2  dt=1e-4  Ma_T~0.83
#
# Usage:
#   cd /mnt/e/SRC_MPCD_DEV/SRC_GPU-SURF
#   LIVE_PROGRESS=1 bash scripts/run_0493x24q_sato_mach_stationarity_overnight.sh
#
# Optional:
#   T_FORCED=4.0 ... bash scripts/run_0493x24q_sato_mach_stationarity_overnight.sh
#   START_CASE=M017 ... bash scripts/run_0493x24q_sato_mach_stationarity_overnight.sh
# =============================================================================

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT" || exit 2

SEED="${SEED:-493205}"
T_RELAX="${T_RELAX:-0.4}"
T_FORCED="${T_FORCED:-6.0}"
TARGET_H_OVER_D="${TARGET_H_OVER_D:-0.8}"
DARCY_ALPHA_MAX="${DARCY_ALPHA_MAX:-800000}"
INACTIVE_SLOTS_CELL_FRACTION="${INACTIVE_SLOTS_CELL_FRACTION:-24.0}"
SUMMARY_EVERY="${SUMMARY_EVERY:-100}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
START_CASE="${START_CASE:-M067}"

RELAX_RUNNER="scripts/run_0493x24h_sato_short_nozzle_relax.sh"
FORCED_RUNNER="scripts/run_0493x24i_sato_short_nozzle_forced.sh"

BASE_STATE="${BASE_STATE:-runs/0493x24h_sato_short_nozzle_relax_seed493205/restart_short_nozzle_relax/output/state_step_00002000.smpcd}"
BASE_ROOT="${BASE_ROOT:-runs/0493x24q_sato_mach_stationarity_seed${SEED}}"

GAS_MASS="0.0011735205616850552"
JET_SPEED="5.9694820421182504"

if [[ ! -f "$BASE_STATE" ]]; then
  echo "[0493x24q] ERROR missing common base state: $BASE_STATE" >&2
  exit 2
fi
if [[ ! -f "$RELAX_RUNNER" ]]; then
  echo "[0493x24q] ERROR missing relax runner: $RELAX_RUNNER" >&2
  exit 2
fi
if [[ ! -f "$FORCED_RUNNER" ]]; then
  echo "[0493x24q] ERROR missing forced runner: $FORCED_RUNNER" >&2
  exit 2
fi

mkdir -p "$BASE_ROOT" || exit 2

PLAN="$BASE_ROOT/campaign_plan.tsv"
STATUS="$BASE_ROOT/campaign_status.tsv"

printf "case\tkBT_over_m\tgas_kBT\tdt\tMa_proxy\tT_relax\trelax_steps\tT_forced\tforced_steps\tinactive_fraction\n" > "$PLAN"
printf "case\tstage\tstatus\tpath\n" > "$STATUS"

# label  kBT/m  dt
CASES=(
  "M067 0.8 0.0004"
  "M033 3.2 0.0004"
  "M017 12.8 0.0002"
  "M008 51.2 0.0001"
)

started=0

for spec in "${CASES[@]}"; do
  read -r TAG KM DT <<<"$spec"

  if [[ "$started" == "0" ]]; then
    if [[ "$TAG" == "$START_CASE" ]]; then
      started=1
    else
      continue
    fi
  fi

  read -r GAS_KBT MACH RELAX_STEPS FORCED_STEPS ANALYSIS_START DUMP_EVERY <<<"$(
    python3 - "$GAS_MASS" "$KM" "$JET_SPEED" "$DT" "$T_RELAX" "$T_FORCED" <<'PY'
import math, sys
mg, km, u, dt, tr, tf = map(float, sys.argv[1:])
kg = mg * km
mach = u / math.sqrt(km)
nr = int(round(tr / dt))
nf = int(round(tf / dt))
if abs(nr*dt-tr) > 1e-12 or abs(nf*dt-tf) > 1e-12:
    raise SystemExit("physical duration is not an integer number of steps")
analysis_start = int(round(0.75 * nf))
# restart checkpoint every 1.0 physical time unit
dump_every = max(1, int(round(1.0 / dt)))
print(f"{kg:.17g}", f"{mach:.12g}", nr, nf, analysis_start, dump_every)
PY
  )" || exit 2

  printf "%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n" \
    "$TAG" "$KM" "$GAS_KBT" "$DT" "$MACH" \
    "$T_RELAX" "$RELAX_STEPS" "$T_FORCED" "$FORCED_STEPS" \
    "$INACTIVE_SLOTS_CELL_FRACTION" >> "$PLAN"

  echo
  echo "================================================================"
  echo "[0493x24q] CASE=$TAG"
  echo "[0493x24q] kBT/m=$KM gasKBT=$GAS_KBT dt=$DT Ma_proxy=$MACH"
  echo "[0493x24q] relax: T=$T_RELAX steps=$RELAX_STEPS"
  echo "[0493x24q] forced: T=$T_FORCED steps=$FORCED_STEPS lateWindow=$ANALYSIS_START:$FORCED_STEPS"
  echo "[0493x24q] inactiveFraction=$INACTIVE_SLOTS_CELL_FRACTION dumpEvery=$DUMP_EVERY"
  echo "================================================================"

  # ---------------------------------------------------------------------------
  # A. Equal-duration zero-jet thermal relaxation from the SAME common state.
  # ---------------------------------------------------------------------------
  RELAX_ROOT="$BASE_ROOT/${TAG}_relax"
  RELAX_LABEL="0493x24q_${TAG}_relax"

  echo "[0493x24q] $TAG relax preflight"
  RESTART=1 \
  RESTART_STATE="$BASE_STATE" \
  RESTART_FROM_STEP=2000 \
  RESTART_TAG="relax" \
  CAMPAIGN_ROOT="$RELAX_ROOT" \
  CASE_LABEL="$RELAX_LABEL" \
  TARGET_H_OVER_D="$TARGET_H_OVER_D" \
  GAS_KBT="$GAS_KBT" \
  GAS_KBT_OVER_MASS_REF="$KM" \
  DT="$DT" \
  DARCY_ALPHA_MAX="$DARCY_ALPHA_MAX" \
  STEPS="$RELAX_STEPS" \
  ANALYSIS_START_STEP="$((RELAX_STEPS/2))" \
  ANALYSIS_END_STEP="$RELAX_STEPS" \
  DUMP_STATE_EVERY="$RELAX_STEPS" \
  DUMP_ROLE_FILTER=all \
  SUMMARY_EVERY="$SUMMARY_EVERY" \
  PREFLIGHT_ONLY=1 \
  LIVE_PROGRESS="$LIVE_PROGRESS" \
  bash "$RELAX_RUNNER"

  rc=$?
  if [[ "$rc" != "0" ]]; then
    printf "%s\trelax_preflight\tFAIL\t%s\n" "$TAG" "$RELAX_ROOT" >> "$STATUS"
    echo "[0493x24q] ERROR $TAG relax preflight rc=$rc" >&2
    exit "$rc"
  fi

  echo "[0493x24q] $TAG relax run"
  RESTART=1 \
  RESTART_STATE="$BASE_STATE" \
  RESTART_FROM_STEP=2000 \
  RESTART_TAG="relax" \
  CAMPAIGN_ROOT="$RELAX_ROOT" \
  CASE_LABEL="$RELAX_LABEL" \
  TARGET_H_OVER_D="$TARGET_H_OVER_D" \
  GAS_KBT="$GAS_KBT" \
  GAS_KBT_OVER_MASS_REF="$KM" \
  DT="$DT" \
  DARCY_ALPHA_MAX="$DARCY_ALPHA_MAX" \
  STEPS="$RELAX_STEPS" \
  ANALYSIS_START_STEP="$((RELAX_STEPS/2))" \
  ANALYSIS_END_STEP="$RELAX_STEPS" \
  DUMP_STATE_EVERY="$RELAX_STEPS" \
  DUMP_ROLE_FILTER=all \
  SUMMARY_EVERY="$SUMMARY_EVERY" \
  PREFLIGHT_ONLY=0 \
  LIVE_PROGRESS="$LIVE_PROGRESS" \
  bash "$RELAX_RUNNER"

  rc=$?
  if [[ "$rc" != "0" ]]; then
    printf "%s\trelax\tFAIL\t%s\n" "$TAG" "$RELAX_ROOT" >> "$STATUS"
    echo "[0493x24q] ERROR $TAG relax rc=$rc" >&2
    exit "$rc"
  fi

  RELAX_STEP_PAD="$(printf "%08d" "$RELAX_STEPS")"
  RELAX_STATE="$RELAX_ROOT/restart_relax/output/state_step_${RELAX_STEP_PAD}.smpcd"

  if [[ ! -f "$RELAX_STATE" ]]; then
    printf "%s\trelax_dump\tFAIL\t%s\n" "$TAG" "$RELAX_STATE" >> "$STATUS"
    echo "[0493x24q] ERROR missing relaxed state: $RELAX_STATE" >&2
    exit 2
  fi
  printf "%s\trelax\tPASS\t%s\n" "$TAG" "$RELAX_STATE" >> "$STATUS"

  # ---------------------------------------------------------------------------
  # B. Long forced run, same Ujet/Fr/We/Bo/H/D, smooth ramp only at this start.
  # ---------------------------------------------------------------------------
  FORCED_ROOT="$BASE_ROOT/${TAG}_forced"
  FORCED_LABEL="0493x24q_${TAG}_forced"

  echo "[0493x24q] $TAG forced preflight"
  RESTART=1 \
  RESTART_STATE="$RELAX_STATE" \
  RESTART_FROM_STEP="$RELAX_STEPS" \
  RESTART_TAG="forced" \
  CAMPAIGN_ROOT="$FORCED_ROOT" \
  CASE_LABEL="$FORCED_LABEL" \
  TARGET_H_OVER_D="$TARGET_H_OVER_D" \
  GAS_KBT="$GAS_KBT" \
  GAS_KBT_OVER_MASS_REF="$KM" \
  DT="$DT" \
  DARCY_ALPHA_MAX="$DARCY_ALPHA_MAX" \
  JET_RAMP_START_TIME=0.0 \
  JET_RAMP_END_TIME=0.20 \
  JET_RAMP_INITIAL_FACTOR=0.0 \
  JET_RAMP_FINAL_FACTOR=1.0 \
  INACTIVE_SLOTS_CELL_FRACTION="$INACTIVE_SLOTS_CELL_FRACTION" \
  STEPS="$FORCED_STEPS" \
  ANALYSIS_START_STEP="$ANALYSIS_START" \
  ANALYSIS_END_STEP="$FORCED_STEPS" \
  DUMP_STATE_EVERY="$DUMP_EVERY" \
  DUMP_ROLE_FILTER=all \
  SUMMARY_EVERY="$SUMMARY_EVERY" \
  PREFLIGHT_ONLY=1 \
  LIVE_PROGRESS="$LIVE_PROGRESS" \
  bash "$FORCED_RUNNER"

  rc=$?
  if [[ "$rc" != "0" ]]; then
    printf "%s\tforced_preflight\tFAIL\t%s\n" "$TAG" "$FORCED_ROOT" >> "$STATUS"
    echo "[0493x24q] ERROR $TAG forced preflight rc=$rc" >&2
    exit "$rc"
  fi

  echo "[0493x24q] $TAG forced run"
  RESTART=1 \
  RESTART_STATE="$RELAX_STATE" \
  RESTART_FROM_STEP="$RELAX_STEPS" \
  RESTART_TAG="forced" \
  CAMPAIGN_ROOT="$FORCED_ROOT" \
  CASE_LABEL="$FORCED_LABEL" \
  TARGET_H_OVER_D="$TARGET_H_OVER_D" \
  GAS_KBT="$GAS_KBT" \
  GAS_KBT_OVER_MASS_REF="$KM" \
  DT="$DT" \
  DARCY_ALPHA_MAX="$DARCY_ALPHA_MAX" \
  JET_RAMP_START_TIME=0.0 \
  JET_RAMP_END_TIME=0.20 \
  JET_RAMP_INITIAL_FACTOR=0.0 \
  JET_RAMP_FINAL_FACTOR=1.0 \
  INACTIVE_SLOTS_CELL_FRACTION="$INACTIVE_SLOTS_CELL_FRACTION" \
  STEPS="$FORCED_STEPS" \
  ANALYSIS_START_STEP="$ANALYSIS_START" \
  ANALYSIS_END_STEP="$FORCED_STEPS" \
  DUMP_STATE_EVERY="$DUMP_EVERY" \
  DUMP_ROLE_FILTER=all \
  SUMMARY_EVERY="$SUMMARY_EVERY" \
  PREFLIGHT_ONLY=0 \
  LIVE_PROGRESS="$LIVE_PROGRESS" \
  bash "$FORCED_RUNNER"

  rc=$?
  if [[ "$rc" != "0" ]]; then
    printf "%s\tforced\tFAIL\t%s\n" "$TAG" "$FORCED_ROOT" >> "$STATUS"
    echo "[0493x24q] ERROR $TAG forced rc=$rc" >&2
    exit "$rc"
  fi

  printf "%s\tforced\tPASS\t%s\n" "$TAG" "$FORCED_ROOT" >> "$STATUS"
  echo "[0493x24q] CASE=$TAG COMPLETE"
done

echo
echo "================================================================"
echo "[0493x24q] CAMPAIGN COMPLETE"
echo "[0493x24q] root=$BASE_ROOT"
echo "[0493x24q] plan=$PLAN"
echo "[0493x24q] status=$STATUS"
echo "================================================================"
