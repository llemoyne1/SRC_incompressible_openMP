#!/usr/bin/env bash
# 0493x14bc pulsed Basilisk control: calibrated cold liquid, 5% inlet sinusoid ON.
# Deliberately no `set -euo pipefail`.
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export BASILISK_PULSE_RUNTIME_ENABLE="${BASILISK_PULSE_RUNTIME_ENABLE:-1}"
export CASE_LABEL="${CASE_LABEL:-0493x14bc_basilisk2d_Re500_WeG200_D96_cold_pulsed}"
export BASE_RUN_ROOT="${BASE_RUN_ROOT:-runs/0493x14bc_basilisk_atomisation_Re500_cold_pulsed_seed${SEED:-493215}}"
exec bash "$ROOT/scripts/run_0493x14bc_basilisk_atomisation_cold_re500.sh" "$@"
