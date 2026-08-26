#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

SEED="${SEED:-493952}"
MODES="${MODES:-x10o x10r}"
VYS="${VYS:--0.1 0.1}"
LOG_ROOT="${LOG_ROOT:-runs/0493x10micro_logs}"
mkdir -p "$LOG_ROOT"

echo "===== 0493x10 MICRO-REFLECTION R2 / 10 STEPS ====="
echo "[0493x10micro-run] seed=$SEED modes='$MODES' Vys='$VYS' (odd pair only)"
echo "[0493x10micro-run] R/h=2 sigma=0 g=0, dumps + summaries every step"
echo "[0493x10micro-run] event trace is diagnostic only"

for MODE in $MODES; do
  case "$MODE" in
    x10o)
      X10R=0
      ;;
    x10r)
      X10R=1
      ;;
    *)
      echo "[0493x10micro-run] ERROR unknown mode=$MODE (x10o|x10r)" >&2
      exit 2
      ;;
  esac

  for VY in $VYS; do
    TAG="$(printf '%s' "$VY" | sed 's/-/m/; s/+//; s/\./p/')"
    RUN_ROOT="runs/0493x10micro_R2_${MODE}_vy${TAG}"
    LOG="$LOG_ROOT/${MODE}_vy${TAG}.console.log"

    echo
    echo "[0493x10micro-run] START mode=$MODE Vy=$VY root=$RUN_ROOT"

    MPCD_X10_MICRO_REFLECTION_TRACE=1 \
    MPCD_X10R_Q6_THERMAL_FULL_VECTOR_ENDPOINT_VELOCITY="$X10R" \
    MPCD_X10S_Q6_THERMAL_SEGMENT_NORMAL_KINEMATICS=0 \
    MPCD_X10T_Q6_THERMAL_RIGID_TANGENTIAL_KINEMATICS=0 \
    SEED="$SEED" \
    RUN_ROOT="$RUN_ROOT" \
    NX=800 NY=400 \
    Lx=3.125 Ly=1.5625 \
    GAMMA=20 \
    DT=0.002 \
    KBT=0.125 \
    LIQUID_MASS=1.0 \
    DROP_RADIUS_CELLS=2 \
    DROP_CENTER_X=1.5625 \
    DROP_CENTER_Y=0.78125 \
    DROP_VX=0.0 \
    DROP_VY="$VY" \
    SIGMA_ACTIVE=0 \
    CONTACT_ANGLE_DEG=-1 \
    GRAVITY_Y=0.0 \
    STEPS=10 \
    SUMMARY_EVERY=1 \
    DUMP_STATE_EVERY=1 \
    LIVE_PROGRESS=1 \
    LIVE_VIS_ENABLE=0 \
    LIVE_VIS_RECORD_ENABLE=0 \
    FILTERED_RECORDING_ENABLE=0 \
    LIVE_VIS_HOLD_ON_EXIT=0 \
    CLEAN_RUN_ROOT=1 \
    bash scripts/run_0493x10o_q6_thermal_interface_static_drop.sh \
      2>&1 | tee "$LOG"

    echo "[0493x10micro-run] DONE mode=$MODE Vy=$VY log=$LOG"
  done
done

echo
echo "[0493x10micro-run] complete"
echo "[0493x10micro-run] dumps: runs/0493x10micro_R2_*/output/state_step_*.smpcd"
echo "[0493x10micro-run] traces: $LOG_ROOT/*.console.log"
