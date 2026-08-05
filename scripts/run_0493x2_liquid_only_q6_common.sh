#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"

# Full-grid Q6 control: unlike independent_masked, common keeps the pressure
# solve on every geometric cell after a transiently empty liquid cell appears.
export SPECIES_Q6_MODE=common
export RUN_MODES=src-q6
export DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-100}"
export BASE_RUN_ROOT="${BASE_RUN_ROOT:-runs/0493x2_liquid_only_${NX:-200}x${NY:-200}_g${GAMMA:-10}_src-q6_common}"

exec bash "$ROOT/scripts/run_0493x2_liquid_only_q6.sh"
