#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"
for f in scripts/calibrate_src_transport_0493x13j.sh scripts/analyze_0493x13j_src_transport.py; do
  [[ -f "$f" ]] || { echo "[0493x13j-check] ERROR missing $f" >&2; exit 2; }
done
bash -n scripts/calibrate_src_transport_0493x13j.sh
python3 -m py_compile scripts/analyze_0493x13j_src_transport.py
python3 scripts/analyze_0493x13j_src_transport.py --self-test --campaign-root runs/_0493x13j_dummy --repo-root "$ROOT"
TMP="runs/_0493x13j_check_${$}"
trap 'rm -rf "$TMP"' EXIT
RUN_ROOT="$TMP" PREFLIGHT_ONLY=1 CLEAN_ROOT=1 LIVE_VIS_ENABLE=1 LIVE_VIS_EVERY=1 \
  bash scripts/calibrate_src_transport_0493x13j.sh >/tmp/0493x13j_check_src.log
RUN_ROOT="$TMP.q6gf" CALIBRATION_PATH=src-q6-g-f PREFLIGHT_ONLY=1 CLEAN_ROOT=1 LIVE_VIS_ENABLE=1 LIVE_VIS_EVERY=1 \
  bash scripts/calibrate_src_transport_0493x13j.sh >/tmp/0493x13j_check_q6gf.log
rm -rf "$TMP.q6gf"
grep -q 'effectivePathAudit=PASS' /tmp/0493x13j_check_src.log
grep -q 'effectivePathAudit=PASS' /tmp/0493x13j_check_q6gf.log
grep -q 'PREFLIGHT PASS' /tmp/0493x13j_check_src.log
grep -q 'PREFLIGHT PASS' /tmp/0493x13j_check_q6gf.log
rm -f /tmp/0493x13j_check_src.log /tmp/0493x13j_check_q6gf.log
echo '[0493x13j-check] PASS syntax + fit self-test + SRC/Q6GF preflights'
