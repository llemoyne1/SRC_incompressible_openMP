#!/usr/bin/env bash
set -euo pipefail
BASE=${BASE:-runs/0435c_compare}
REPORT=${REPORT:-runs/0435c_boundary_equivalence_report.txt}
mkdir -p "$(dirname "$REPORT")"
python3 scripts/summarize_0435c_boundary_equivalence.py --base "$BASE" > "$REPORT"
echo "[0435c-equivalence] wrote $REPORT"
cat "$REPORT"
