#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
python3 scripts/summarize_0435c_levelB.py "$@" | tee runs/0435c_levelB_summary.txt
