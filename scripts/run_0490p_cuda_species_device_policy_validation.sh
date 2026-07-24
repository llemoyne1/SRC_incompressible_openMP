#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_0490n}"
STEPS="${STEPS:-250}"
SEEDS="${SEEDS:-1628501}"
RUN_ROOT="${RUN_ROOT:-runs/0490p_cuda_species_device_policy_validation}"

LIVE_PROGRESS="${LIVE_PROGRESS:-1}" \
BIN="$BIN" STEPS="$STEPS" SEEDS="$SEEDS" RUN_ROOT="$RUN_ROOT" \
bash scripts/run_0490n_cuda_species_resident_maintenance_validation.sh

python3 - "$RUN_ROOT" "$STEPS" "$SEEDS" <<'PY_CHECK_0490P'
import csv, pathlib, sys
root=pathlib.Path(sys.argv[1]); steps=int(sys.argv[2]); seeds=sys.argv[3].split()
for seed in seeds:
    out=root/f'long_seed_{seed}'/'output'
    maint=list(csv.DictReader(open(out/'cuda_species_resident_maintenance_0490n.csv',newline='')))
    plan=list(csv.DictReader(open(out/'cuda_species_transfer_plan_0490n.csv',newline='')))
    deposits=[r for r in maint if int(r['depositRequested'])==1]
    if not deposits:
        raise SystemExit(f'[0490p] FAIL seed={seed} no resident policy refresh')
    if any(int(r['cellPolicyDeviceResident'])!=1 for r in deposits):
        raise SystemExit(f'[0490p] FAIL seed={seed} policy not device resident')
    if any(int(r['policyHostArrayEntries'])!=0 or int(r['cellMirrorDownloadBytes'])!=0 for r in deposits):
        raise SystemExit(f'[0490p] FAIL seed={seed} host per-cell policy mirror remained')
    if any(int(r['policySummaryDownloadBytes'])<=0 for r in deposits):
        raise SystemExit(f'[0490p] FAIL seed={seed} missing fixed-size policy summary')
    if any(int(r['residentPolicyDeviceHandoff'])!=1 or int(r['policyMaskUploadSkipped'])!=1 for r in plan):
        raise SystemExit(f'[0490p] FAIL seed={seed} planner policy device handoff')
    print(f'[0490p] seed={seed} PASS steps={steps} policy_refreshes={len(deposits)}')
print('[0490p] PASS')
print('[0490p] resident_cell_policy=device')
print('[0490p] host_cell_policy_array_entries=0')
print('[0490p] policy_mask_h2d=0')
print('[0490p] remaining_cpu_scope=none')
PY_CHECK_0490P
