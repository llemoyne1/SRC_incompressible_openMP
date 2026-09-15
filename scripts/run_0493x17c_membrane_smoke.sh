#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"
SMOKE_ROOT="${SMOKE_ROOT:-runs/0493x17c_membrane_smoke}"
rm -rf "$SMOKE_ROOT"

# Short loaded membrane: enough to exercise contour extraction, nodal impact
# projection, elastic kick, drift, and the penetration diagnostic.
FRAME_LABEL=rest \
BASE_RUN_ROOT="$SMOKE_ROOT/loaded_rest" \
CASE_LABEL=0493x17c_membrane_smoke \
Lx=0.5 Ly=0.375 NX=128 NY=96 GAMMA=12 STEPS="${STEPS:-200}" DT=0.002 \
CIRCLE_CX=0.25 CIRCLE_CY=0.1875 CIRCLE_R=0.0625 \
RELATIVE_UX=0.08 BOOST_UX=0.0 \
SOLID_MASS=4096 MEMBRANE_K_STRETCH=200000 MEMBRANE_K_AREA=200000 MEMBRANE_DAMPING=500 \
SUMMARY_EVERY=1 MEMBRANE_OUTPUT_EVERY=50 RECORD_EVERY=50 \
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}" LIVE_PROGRESS="${LIVE_PROGRESS:-1}" \
CLEAN_RUN_ROOT=1 \
bash scripts/run_0493x17c_membrane_fsi_case.sh

python3 - "$SMOKE_ROOT/loaded_rest/fresh/output" <<'PY'
import csv, math, sys
from pathlib import Path
out=Path(sys.argv[1])
with (out/'chi_penetration_0493x16l.csv').open(newline='') as f:
    pen=list(csv.DictReader(f))
with (out/'chi_membrane_0493x17c.csv').open(newline='') as f:
    mem=list(csv.DictReader(f))
strict=max(int(float(r['strictInsideParticles'])) for r in pen)
depth=max(float(r['maxPenetrationCells']) for r in pen)
proj=max(math.hypot(float(r['loadProjectionResidualX']),float(r['loadProjectionResidualY'])) for r in mem)
strain=max(float(r['maxAbsEdgeStrain']) for r in mem)
stab=max(float(r['stabilityNumber']) for r in mem)
print(f"strictInsideMax={strict} maxPenetrationCells={depth:.9g} loadProjectionAbsMax={proj:.3e} maxStrain={strain:.6g} stability={stab:.6g}")
if strict != 0 or depth > 1e-6 or not math.isfinite(strain) or stab > 0.35:
    raise SystemExit(3)
print('0493x17c membrane smoke: PASS')
PY
