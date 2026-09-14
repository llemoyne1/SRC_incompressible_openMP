#!/usr/bin/env bash
set -u
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT" || exit $?
BASE="${BASE_RUN_ROOT:-runs/0493x17b_initialization_smoke}"
rm -rf "$BASE"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
SRC_X16I_STATIC_CURVED_0493X16M=1 \
BASE_RUN_ROOT="$BASE/static_curved/rest" CASE_LABEL=0493x17b_static_init_smoke \
COMMON_UX=0.0 DEFORMABLE=1 INITIAL_DEACTIVATE_BELOW_CHI=0.5 \
STEPS=20 SUMMARY_EVERY=1 DUMP_STATE_EVERY=0 CLEAN_RUN_ROOT=1 \
LIVE_VIS_ENABLE="$LIVE_VIS_ENABLE" FILTERED_RECORDING_ENABLE=0 RECORD_ENABLE=false \
bash scripts/run_0493x17a_lagrangian_boundary_case.sh || exit $?
python3 - "$BASE/static_curved/rest/fresh/output/chi_penetration_0493x16l.csv" <<'PY'
import csv,sys
p=sys.argv[1]
with open(p,newline='') as f: r=list(csv.DictReader(f))
if not r: raise SystemExit('[0493x17b] ERROR empty penetration CSV')
mx=max(int(float(x['strictInsideParticles'])) for x in r)
mp=max(float(x['maxPenetrationCells']) for x in r)
print(f'[0493x17b] static_curved smoke rows={len(r)} maxStrictInsideParticles={mx} maxPenetrationCells={mp:.17g}')
if mx!=0 or mp>1e-6: raise SystemExit(3)
print('0493x17b initialization smoke: PASS')
PY
