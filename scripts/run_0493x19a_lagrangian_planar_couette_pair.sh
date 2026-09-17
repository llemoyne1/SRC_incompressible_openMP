#!/usr/bin/env bash
# 0493x19a paired ablation: historical specular versus new bounceback response.
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT" || exit $?
BASE="${BASE_RUN_ROOT:-runs/0493x19a_lagrangian_planar_couette_pair}"
STEPS="${STEPS:-5000}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"

KINETIC_MODE=specular CASE_LABEL=0493x19a_specular \
BASE_RUN_ROOT="$BASE/specular" STEPS="$STEPS" LIVE_VIS_ENABLE="$LIVE_VIS_ENABLE" \
bash scripts/run_0493x19a_lagrangian_planar_couette.sh || exit $?

KINETIC_MODE=bounceback CASE_LABEL=0493x19a_bounceback \
BASE_RUN_ROOT="$BASE/bounceback" STEPS="$STEPS" LIVE_VIS_ENABLE="$LIVE_VIS_ENABLE" \
bash scripts/run_0493x19a_lagrangian_planar_couette.sh || exit $?

echo "[0493x19a-pair] COMPLETE base=$BASE"
