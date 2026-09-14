#!/usr/bin/env bash
set -u
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"; cd "$ROOT" || exit $?
BASE="${BASE_RUN_ROOT:-runs/0493x17a_lagrangian_boundary_smoke}"
rm -rf "$BASE"
bash scripts/check_0493x17a_lagrangian_boundary.sh || exit $?
BASE_RUN_ROOT="$BASE/rigid_rest" CASE_LABEL=0493x17a_smoke_rigid_rest COMMON_UX=0 DEFORMABLE=0 STEPS=150 SUMMARY_EVERY=1 DUMP_STATE_EVERY=0 CLEAN_RUN_ROOT=1 FILTERED_RECORDING_ENABLE=0 RECORD_ENABLE=false bash scripts/run_0493x17a_lagrangian_boundary_case.sh || exit $?
BASE_RUN_ROOT="$BASE/deform_rest" CASE_LABEL=0493x17a_smoke_deform_rest COMMON_UX=0 DEFORMABLE=1 STEPS=200 SUMMARY_EVERY=1 DUMP_STATE_EVERY=0 CLEAN_RUN_ROOT=1 FILTERED_RECORDING_ENABLE=0 RECORD_ENABLE=false bash scripts/run_0493x17a_lagrangian_boundary_case.sh || exit $?
python3 - "$BASE" <<'PY'
import csv,sys
from pathlib import Path
base=Path(sys.argv[1])
for name in ('rigid_rest','deform_rest'):
 p=base/name/'fresh/output/chi_penetration_0493x16l.csv'
 with p.open(newline='') as f: r=list(csv.DictReader(f))
 ms=max(int(float(x['strictInsideParticles'])) for x in r); mp=max(float(x['maxPenetrationCells']) for x in r)
 print(f'{name}: maxStrictInsideParticles={ms} maxPenetrationCells={mp:.17g}')
 if ms!=0 or mp>1e-6: raise SystemExit(3)
print('0493x17a smoke: PASS')
PY
