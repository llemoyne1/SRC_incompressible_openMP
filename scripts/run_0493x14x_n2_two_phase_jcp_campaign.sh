#!/usr/bin/env bash

# JCP campaign wrapper for the existing qualified x14x two-phase n=2 runner.
# No compilation. No C++/CUDA modification.
# Uses three seeds matched to the n=3 campaign.

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT" || exit 2

RUNNER="$ROOT/scripts/run_ok_0493x14x_two_phase_oscillating_drop_n2.sh"
if [[ ! -f "$RUNNER" ]]; then
  echo "[n2-jcp] ERROR missing historical runner: $RUNNER" >&2
  exit 2
fi

BIN="${BIN:-$ROOT/build/src_mpcd_base_cuda_q6_resident_livevis_0486}"
if [[ ! -x "$BIN" ]]; then
  echo "[n2-jcp] ERROR frozen binary not found/executable: $BIN" >&2
  exit 2
fi

SEEDS=(493180 493181 493182)

for SEED_VALUE in "${SEEDS[@]}"; do
  CASE="0493x14x_n2_two_phase_jcp_seed${SEED_VALUE}"
  ROOT_RUN="runs/${CASE}"

  echo
  echo "================================================================"
  echo "[n2-jcp] seed=$SEED_VALUE"
  echo "[n2-jcp] runRoot=$ROOT_RUN"
  echo "[n2-jcp] frozen binary=$BIN"
  echo "================================================================"

  SEED="$SEED_VALUE" \
  CASE_LABEL="$CASE" \
  CAMPAIGN_ROOT="$ROOT_RUN" \
  BIN="$BIN" \
  GAMMA=20 \
  DT=0.002 \
  STEPS=3000 \
  RADIUS_CELLS=40 \
  MODE=2 \
  EPSILON=0.04 \
  LIQUID_MASS=1.0 \
  GAS_MASS=0.1 \
  LIQUID_KBT=0.02 \
  GAS_KBT=0.08 \
  SURFACE_TENSION_SIGMA=2560.0 \
  LIVE_PROGRESS=1 \
  LIVE_VIS_ENABLE=1 \
  LIVE_VIS_EVERY=1 \
  RECORD_ENABLE=true \
  RECORD_EVERY=100 \
  DUMP_STATE_EVERY=1000 \
  FIT_PERIODS=2.0 \
  CLEAN_RUN_ROOT=1 \
  bash "$RUNNER"

  rc=$?
  if [[ $rc -ne 0 ]]; then
    echo "[n2-jcp] ERROR seed $SEED_VALUE failed with rc=$rc" >&2
    exit "$rc"
  fi
done

echo
echo "[n2-jcp] DONE: seeds 493180 493181 493182"
echo "[n2-jcp] roots:"
for SEED_VALUE in "${SEEDS[@]}"; do
  echo "  runs/0493x14x_n2_two_phase_jcp_seed${SEED_VALUE}"
done
