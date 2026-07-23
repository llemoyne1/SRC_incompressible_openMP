#!/usr/bin/env bash
set -euo pipefail

BIN="${BIN:-build/src_mpcd_base_cuda_q6_resident_0490n}"
STEPS="${STEPS:-1700}"
SEED="${SEED:-1628501}"
RUN_ROOT="${RUN_ROOT:-runs/0490n_fix2_multi_transfer_materializer_validation}"

if [[ ! -x "$BIN" ]]; then
  echo "[0490n-fix2] FAIL missing executable BIN=$BIN" >&2
  exit 2
fi

LIVE_PROGRESS="${LIVE_PROGRESS:-1}" \
BIN="$BIN" \
STEPS="$STEPS" \
SEEDS="$SEED" \
RUN_ROOT="$RUN_ROOT" \
bash scripts/run_0490n_cuda_species_resident_maintenance_validation.sh

CSV="$RUN_ROOT/nonregression_0490m/long_seed_${SEED}/output/cuda_species_resident_fast_path_0490m.csv"
python3 - "$CSV" <<'PY'
import csv
import sys
from pathlib import Path

path = Path(sys.argv[1])
if not path.is_file():
    raise SystemExit(f"[0490n-fix2] FAIL missing CSV {path}")
rows = list(csv.DictReader(path.open(newline="")))
required = {
    "pass", "invalidOperations", "entryMassShortfalls",
    "donorTypeGroupUnderfills", "plannedMass", "selectedMass",
    "selectedMassCoverageFraction",
}
if not rows or not required.issubset(rows[0]):
    missing = sorted(required - (set(rows[0]) if rows else set()))
    raise SystemExit(f"[0490n-fix2] FAIL missing columns {missing}")

shortfall_rows = [r for r in rows if int(r["entryMassShortfalls"]) > 0]
if not shortfall_rows:
    raise SystemExit("[0490n-fix2] FAIL no discrete entry shortfall was exercised")
for r in shortfall_rows:
    if int(r["pass"]) != 1:
        raise SystemExit(f"[0490n-fix2] FAIL step={r['step']} fast path did not pass")
    if int(r["invalidOperations"]) != 0:
        raise SystemExit(
            f"[0490n-fix2] FAIL step={r['step']} structural invalidOperations="
            f"{r['invalidOperations']}"
        )
    if int(r["donorTypeGroupUnderfills"]) != 0:
        raise SystemExit(
            f"[0490n-fix2] FAIL step={r['step']} donor/type underfills="
            f"{r['donorTypeGroupUnderfills']}"
        )
    if float(r["selectedMass"]) + 1.0e-12 < float(r["plannedMass"]):
        raise SystemExit(
            f"[0490n-fix2] FAIL step={r['step']} selected mass below planned mass"
        )

first = shortfall_rows[0]
print(
    "[0490n-fix2] PASS "
    f"first_shortfall_step={first['step']} "
    f"entry_shortfalls={first['entryMassShortfalls']} "
    f"group_underfills={first['donorTypeGroupUnderfills']} "
    f"planned_mass={first['plannedMass']} "
    f"selected_mass={first['selectedMass']} "
    f"coverage={first['selectedMassCoverageFraction']}"
)
print(f"[0490n-fix2] CSV={path}")
PY
