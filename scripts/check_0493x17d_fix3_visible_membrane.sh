#!/usr/bin/env bash
set -u
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT" || exit $?
python3 scripts/check_0493x17d_fix3_visible_membrane.py || exit $?
bash -n scripts/run_0493x17d_visible_membrane.sh || exit $?
echo "[0493x17d-fix3] CHECK PASS"
