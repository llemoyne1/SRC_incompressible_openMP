#!/usr/bin/env bash
set -u
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT" || exit $?
SPEEDS="${SPEEDS:-0.08 0.12 0.16 0.2}"
SWEEP_ROOT="${SWEEP_ROOT:-runs/0493x18a_hinged_plate_speed_sweep}"
STEPS="${STEPS:-600}"
RECORD_ENABLE="${RECORD_ENABLE:-false}"
for U in $SPEEDS; do
  TAG="$(python3 - "$U" <<'PY'
import sys
u=float(sys.argv[1]); print(f"u{u:.4f}".replace('-','m').replace('.','p'))
PY
)"
  CASE="0493x18a_hinged_${TAG}"
  echo "===== x18a speed sweep FLOW_UX=$U case=$CASE ====="
  FLOW_UX="$U" CASE_LABEL="$CASE" BASE_RUN_ROOT="$SWEEP_ROOT/$TAG" \
    STEPS="$STEPS" RECORD_ENABLE="$RECORD_ENABLE" \
    bash scripts/run_0493x18a_hinged_plate.sh || exit $?
  python3 scripts/analyze_0493x18a_hinged_plate.py --root "$SWEEP_ROOT/$TAG" || exit $?
done
python3 scripts/analyze_0493x18a_hinged_plate_speed_sweep.py --root "$SWEEP_ROOT"
