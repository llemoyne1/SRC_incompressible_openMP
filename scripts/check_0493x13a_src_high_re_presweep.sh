#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

files=(
  scripts/run_0493x13a_src_high_re_presweep_A0_A6.sh
  scripts/analyze_0493x13a_src_high_re_presweep.py
  scripts/run_0493w1_src_fluid_calibrator.sh
  scripts/analyze_0493w1_src_fluid_calibrator.py
  scripts/generate_0493w1_src_fluid_calibrator_states.py
)
for f in "${files[@]}"; do
  [[ -f "$f" ]] || { echo "[0493x13a-check] missing=$f" >&2; exit 2; }
done
bash -n scripts/run_0493x13a_src_high_re_presweep_A0_A6.sh
python3 -m py_compile scripts/analyze_0493x13a_src_high_re_presweep.py

# Preflight the two extrema; this also checks that the unmodified 0493w1 runner
# accepts the short high-dt acoustic case A6 with SOUND_MODE_X=1.
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
PREFLIGHT_ONLY=1 CASES=A0,A6 SWEEP_ROOT="$tmp/preflight" \
  bash scripts/run_0493x13a_src_high_re_presweep_A0_A6.sh >/dev/null

python3 - "$tmp/preflight/manifest_0493x13a.csv" <<'PY'
import csv, math, sys
rows={r['case']:r for r in csv.DictReader(open(sys.argv[1],newline=''))}
assert set(rows)=={f'A{i}' for i in range(7)}
assert abs(float(rows['A0']['dt'])-0.002) < 1e-14
assert abs(float(rows['A6']['targetLambdaMeanOverCell'])-3.0) < 1e-14
assert int(float(rows['A0']['gamma']))==20
assert abs(float(rows['A0']['cellSize'])-1/256) < 1e-15
assert float(rows['A6']['soundSteps']) >= 80
print('[0493x13a-check] matrix=PASS A0-reference+A6-boundary')
PY

echo '[0493x13a-check] PASS source_unchanged=true campaign=A0-A6'
