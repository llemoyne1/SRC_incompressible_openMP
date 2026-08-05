#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
export Q6_FORCE_PROJECTION_MODE=prestream_single
export BASE_RUN_ROOT="${BASE_RUN_ROOT:-runs/0493x4a_liquid_only_q6_force_single_${NX:-200}x${NY:-200}_g${GAMMA:-10}}"

exec bash "$ROOT/scripts/run_0493x3_liquid_only_q6_force_prestream.sh"
