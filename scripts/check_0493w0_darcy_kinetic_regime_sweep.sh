#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
RUNNER="$ROOT/scripts/run_0493w0_darcy_kinetic_regime_sweep.sh"
ANALYZER="$ROOT/scripts/analyze_0493w0_darcy_kinetic_regime_sweep.py"
BASE="$ROOT/scripts/run_0493o0_src_baseline_segmented_darcy.sh"

[[ -x "$RUNNER" ]] || { echo "[0493w0-check] ERROR runner missing/not executable: $RUNNER" >&2; exit 2; }
[[ -f "$ANALYZER" ]] || { echo "[0493w0-check] ERROR analyzer missing: $ANALYZER" >&2; exit 2; }
[[ -x "$BASE" ]] || { echo "[0493w0-check] ERROR base runner missing/not executable: $BASE" >&2; exit 2; }

bash -n "$RUNNER"
python3 -m py_compile "$ANALYZER"

grep -q 'SUPPORT_REPAIR_ENABLE=false' "$RUNNER"
grep -q 'THERMOSTAT_TARGET_KBT="$kbt"' "$RUNNER"
grep -q 'DUMP_STATE_EVERY="$steps"' "$RUNNER"
grep -q 'MachIdeal2dProxy' "$ANALYZER"
grep -q 'ReCylinderEstimate' "$ANALYZER"
grep -q 'wakeToSideMassRatio' "$ANALYZER"
grep -q 'darcyAlphaDt' "$ANALYZER"

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
cat > "$TMP/manifest.csv" <<CSV
case_id,nx,ny,dt,kbt,alpha,steps,t_end,run_root,note
ref,128,128,0.001,0.001,8000,800,0.8,$TMP/ref,check
hot,256,256,0.002,0.1,8000,400,0.8,$TMP/hot,check
CSV
python3 "$ANALYZER" \
  --sweep-root "$TMP" \
  --manifest "$TMP/manifest.csv" \
  --preflight-only > "$TMP/preflight.log"

grep -q 'ref' "$TMP/preflight.log"
grep -q 'hot' "$TMP/preflight.log"
python3 - "$TMP/analysis/dimensionless_preflight.csv" <<'PY'
import csv
import math
import sys
with open(sys.argv[1], newline="") as stream:
    rows = {row["case_id"]: row for row in csv.DictReader(stream)}
assert set(rows) == {"ref", "hot"}
ref = rows["ref"]
hot = rows["hot"]
assert math.isclose(float(ref["input_ReCylinderEstimate"]), 7.4495564122, rel_tol=1e-8)
assert math.isclose(float(ref["input_MachIdeal2dProxy"]), 3.3541019662, rel_tol=1e-8)
assert float(hot["input_ReCylinderEstimate"]) > 45.0
assert float(hot["input_MachIdeal2dProxy"]) < 0.4
assert float(hot["input_thermalDisplacement2dRmsOverCell"]) > 0.2
PY

echo "[0493w0-check] PASS"
