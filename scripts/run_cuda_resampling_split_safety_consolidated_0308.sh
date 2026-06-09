#!/usr/bin/env bash
set -euo pipefail

# 0308 — consolidation validation for nominal CUDA resampling split safety.
#
# This runner reuses the 0306 velocity-outlier diagnostics, but enforces the
# 0307 safe-floor mode that is now the nominal resampling configuration:
#   - prefer the most massive local donor;
#   - do not split donors below a mass floor;
#   - do not create particles below a mass floor;
#   - keep solid-adjacent splitting enabled but protected by the same floor.
#
# The goal is to confirm that the large-|U| / tiny-mass outliers are removed on
# backward-step and Von Karman stress cases while preserving classic comparison
# runs.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

BIN=${BIN:-build/src_mpcd_base_cuda_0308}
ART_DIR=${ART_DIR:-dev_history/artifacts/gpu_cuda_resampling_split_safety_consolidated_0308}
FORCE_REBUILD=${FORCE_REBUILD:-1}
CLEAN_ART_DIR=${CLEAN_ART_DIR:-1}
STOP_ON_FAIL=${STOP_ON_FAIL:-1}
STRICT_COMPLETION=${STRICT_COMPLETION:-1}
STRICT_REQUIRE_WRAPPER_RC0=${STRICT_REQUIRE_WRAPPER_RC0:-0}
STRICT_REQUIRE_NO_OUTLIERS=${STRICT_REQUIRE_NO_OUTLIERS:-1}
# The hard inlet reservoir and the CUDA population guard both consume inactive
# slots.  The previous 0308 default could exhaust the full-face hard inlet
# reservoir on backward-step + resampling before the requested final step.
# Keep this override configurable, but provide a safer validation default.
INACTIVE_SLOTS=${INACTIVE_SLOTS:-250000}

# Nominal split-safety values selected from 0307 diagnostics.
SPLIT_SAFETY_ENABLE=${SPLIT_SAFETY_ENABLE:-1}
SPLIT_PREFER_MAX_MASS_DONOR=${SPLIT_PREFER_MAX_MASS_DONOR:-1}
SPLIT_DONOR_MIN_MASS=${SPLIT_DONOR_MIN_MASS:-0.5}
SPLIT_NEW_PARTICLE_MIN_MASS=${SPLIT_NEW_PARTICLE_MIN_MASS:-0.25}
SOLID_ADJACENT_SPLIT_MODE=${SOLID_ADJACENT_SPLIT_MODE:-0}
SOLID_ADJACENT_DONOR_MIN_MASS=${SOLID_ADJACENT_DONOR_MIN_MASS:-1.0}
SOLID_ADJACENT_HALO_CELLS_0307=${SOLID_ADJACENT_HALO_CELLS_0307:-1}
TINY_MASS_THRESHOLD_0307=${TINY_MASS_THRESHOLD_0307:-0.25}

# Keep the stress-test defaults aligned with 0306/0307.
RUN_STEP=${RUN_STEP:-1}
RUN_VK=${RUN_VK:-1}
RUN_TG_HOLE=${RUN_TG_HOLE:-0}
RUN_POISEUILLE=${RUN_POISEUILLE:-0}
RUN_CLASSIC=${RUN_CLASSIC:-1}
RUN_RESAMPLING=${RUN_RESAMPLING:-1}

STEP_NX=${STEP_NX:-128}; STEP_NY=${STEP_NY:-48}; STEP_STEPS=${STEP_STEPS:-6000}; STEP_UIN=${STEP_UIN:-0.60}
VK_NX=${VK_NX:-128}; VK_NY=${VK_NY:-48}; VK_STEPS=${VK_STEPS:-6000}; VK_UIN=${VK_UIN:-0.45}; VK_THERMOSTAT_ENABLE=${VK_THERMOSTAT_ENABLE:-1}
TG_STEPS=${TG_STEPS:-2000}
POISEUILLE_STEPS=${POISEUILLE_STEPS:-3000}
GUARD_EVERY=${GUARD_EVERY:-1}
FLAG_EVERY=${FLAG_EVERY:-10}
HIGH_U=${HIGH_U:-1.0}
OUTLIER_U=${OUTLIER_U:-$HIGH_U}

if [[ "$CLEAN_ART_DIR" != "0" ]]; then
  rm -rf "$ART_DIR"
fi
mkdir -p "$ART_DIR"

if [[ "$FORCE_REBUILD" != "0" && "$FORCE_REBUILD" != "false" && "$FORCE_REBUILD" != "FALSE" ]]; then
  OUT="$BIN" CUDA_ARCH_FLAGS="${CUDA_ARCH_FLAGS:-}" bash scripts/build_src_mpcd_cuda_0308.sh
elif [[ ! -x "$BIN" ]]; then
  OUT="$BIN" CUDA_ARCH_FLAGS="${CUDA_ARCH_FLAGS:-}" bash scripts/build_src_mpcd_cuda_0308.sh
fi

if [[ ! -x scripts/run_cuda_resampling_outlier_diagnostics_0306.sh ]]; then
  echo "[0308-consolidated] ERROR: missing scripts/run_cuda_resampling_outlier_diagnostics_0306.sh" >&2
  echo "[0308-consolidated] Apply the 0306 diagnostic patch before 0308." >&2
  exit 2
fi

echo "[0308-consolidated] BIN=$BIN"
echo "[0308-consolidated] ART_DIR=$ART_DIR"
echo "[0308-consolidated] split safety: enable=$SPLIT_SAFETY_ENABLE preferMax=$SPLIT_PREFER_MAX_MASS_DONOR donorMin=$SPLIT_DONOR_MIN_MASS newMin=$SPLIT_NEW_PARTICLE_MIN_MASS solidMode=$SOLID_ADJACENT_SPLIT_MODE"
echo "[0308-consolidated] inactive slots override: INACTIVE_SLOTS=$INACTIVE_SLOTS"
echo "[0308-consolidated] strict: completion=$STRICT_COMPLETION requireWrapperRc0=$STRICT_REQUIRE_WRAPPER_RC0 requireNoOutliers=$STRICT_REQUIRE_NO_OUTLIERS"

set +e
env \
  BIN="$BIN" \
  ART_DIR="$ART_DIR" \
  INACTIVE_SLOTS="$INACTIVE_SLOTS" \
  FORCE_REBUILD=0 \
  STOP_ON_FAIL="$STOP_ON_FAIL" \
  RUN_STEP="$RUN_STEP" RUN_VK="$RUN_VK" RUN_TG_HOLE="$RUN_TG_HOLE" RUN_POISEUILLE="$RUN_POISEUILLE" \
  RUN_CLASSIC="$RUN_CLASSIC" RUN_RESAMPLING="$RUN_RESAMPLING" \
  STEP_NX="$STEP_NX" STEP_NY="$STEP_NY" STEP_STEPS="$STEP_STEPS" STEP_UIN="$STEP_UIN" \
  VK_NX="$VK_NX" VK_NY="$VK_NY" VK_STEPS="$VK_STEPS" VK_UIN="$VK_UIN" VK_THERMOSTAT_ENABLE="$VK_THERMOSTAT_ENABLE" \
  GUARD_EVERY="$GUARD_EVERY" FLAG_EVERY="$FLAG_EVERY" HIGH_U="$HIGH_U" OUTLIER_U="$OUTLIER_U" \
  MPCD_CUDA_RESAMPLING_SPLIT_SAFETY_0307="$SPLIT_SAFETY_ENABLE" \
  MPCD_CUDA_RESAMPLING_SPLIT_PREFER_MAX_MASS_DONOR_0307="$SPLIT_PREFER_MAX_MASS_DONOR" \
  MPCD_CUDA_RESAMPLING_SPLIT_DONOR_MIN_MASS_0307="$SPLIT_DONOR_MIN_MASS" \
  MPCD_CUDA_RESAMPLING_SPLIT_NEW_PARTICLE_MIN_MASS_0307="$SPLIT_NEW_PARTICLE_MIN_MASS" \
  MPCD_CUDA_RESAMPLING_SOLID_ADJACENT_SPLIT_MODE_0307="$SOLID_ADJACENT_SPLIT_MODE" \
  MPCD_CUDA_RESAMPLING_SOLID_ADJACENT_DONOR_MIN_MASS_0307="$SOLID_ADJACENT_DONOR_MIN_MASS" \
  MPCD_CUDA_RESAMPLING_SOLID_ADJACENT_HALO_CELLS_0307="$SOLID_ADJACENT_HALO_CELLS_0307" \
  MPCD_CUDA_RESAMPLING_TINY_MASS_THRESHOLD_0307="$TINY_MASS_THRESHOLD_0307" \
  bash scripts/run_cuda_resampling_outlier_diagnostics_0306.sh
rc=$?
set -e

# Provide 0308 aliases for the 0306 analyzer outputs, while preserving the
# original 0306 filenames expected by existing tooling.
for kind in run_manifest per_run timeseries worst_cells; do
  src="$ART_DIR/cuda_resampling_outlier_diagnostics_0306_${kind}.csv"
  dst="$ART_DIR/cuda_resampling_split_safety_consolidated_0308_${kind}.csv"
  if [[ -s "$src" ]]; then
    cp "$src" "$dst"
  fi
done

STRICT_REPORT="$ART_DIR/cuda_resampling_split_safety_consolidated_0308_strict_completion.csv"
if [[ "$STRICT_COMPLETION" != "0" ]]; then
  python3 - "$ART_DIR" "$STRICT_REPORT" "$STEP_STEPS" "$VK_STEPS" "$TG_STEPS" "$POISEUILLE_STEPS" "$HIGH_U" "$STRICT_REQUIRE_WRAPPER_RC0" "$STRICT_REQUIRE_NO_OUTLIERS" <<'PYSTRICT'
import csv, re, sys
from pathlib import Path

art = Path(sys.argv[1])
report = Path(sys.argv[2])
expected = {
    'backward_step': int(float(sys.argv[3])),
    'von_karman_circle': int(float(sys.argv[4])),
    'taylor_green_hole': int(float(sys.argv[5])),
    'poiseuille_wall': int(float(sys.argv[6])),
}
high_u = float(sys.argv[7])
require_wrapper_rc0 = str(sys.argv[8]) not in ('0','false','FALSE','no','NO')
require_no_outliers = str(sys.argv[9]) not in ('0','false','FALSE','no','NO')
manifest = art / 'cuda_resampling_split_safety_consolidated_0308_run_manifest.csv'
timeseries = art / 'cuda_resampling_split_safety_consolidated_0308_timeseries.csv'
per_run = art / 'cuda_resampling_split_safety_consolidated_0308_per_run.csv'

def to_float(v, default=0.0):
    try:
        return float(v)
    except Exception:
        return default

def parse_wrapper_rc(extra):
    m = re.search(r'wrapperRc=([0-9]+)', extra or '')
    return int(m.group(1)) if m else None

if not manifest.exists():
    raise SystemExit(f'missing manifest: {manifest}')
if not timeseries.exists():
    raise SystemExit(f'missing timeseries: {timeseries}')
if not per_run.exists():
    raise SystemExit(f'missing per-run: {per_run}')

last_step = {}
with timeseries.open(newline='') as fh:
    for row in csv.DictReader(fh):
        key = (row.get('caseName',''), row.get('modeName',''))
        st = int(to_float(row.get('step','0'), 0))
        last_step[key] = max(last_step.get(key, 0), st)

per = {}
with per_run.open(newline='') as fh:
    for row in csv.DictReader(fh):
        per[(row.get('caseName',''), row.get('modeName',''))] = row

rows = []
overall_ok = True
with manifest.open(newline='') as fh:
    for row in csv.DictReader(fh):
        case = row.get('caseName','')
        mode = row.get('modeName','')
        key = (case, mode)
        req = expected.get(case, 0)
        last = last_step.get(key, 0)
        completed = (req > 0 and last >= req)
        wrapper_rc = parse_wrapper_rc(row.get('extraEnv',''))
        row_exit = int(to_float(row.get('exitCode','1'), 1))
        prow = per.get(key, {})
        max_worst = to_float(prow.get('maxWorstAbsU','0'), 0)
        high_sum = 0.0
        for k, v in prow.items():
            if k.startswith('sumHighU'):
                high_sum += to_float(v, 0)
        no_outliers = (high_sum == 0.0 and max_worst <= high_u)
        wrapper_ok = (wrapper_rc in (None, 0))
        ok = completed and (wrapper_ok or not require_wrapper_rc0) and (no_outliers or not require_no_outliers) and row_exit == 0
        verdict = 'PASS' if ok else ('PARTIAL' if not completed else 'FAIL')
        if not ok:
            overall_ok = False
        rows.append({
            'caseName': case,
            'modeName': mode,
            'runRoot': row.get('runRoot',''),
            'requestedSteps': req,
            'lastDiagnosticStep': last,
            'completed': int(completed),
            'manifestExitCode': row_exit,
            'wrapperRc': '' if wrapper_rc is None else wrapper_rc,
            'wrapperOk': int(wrapper_ok),
            'maxWorstAbsU': max_worst,
            'sumHighUAllBins': high_sum,
            'noOutliers': int(no_outliers),
            'verdict': verdict,
        })

report.parent.mkdir(parents=True, exist_ok=True)
with report.open('w', newline='') as fh:
    fieldnames = ['caseName','modeName','runRoot','requestedSteps','lastDiagnosticStep','completed','manifestExitCode','wrapperRc','wrapperOk','maxWorstAbsU','sumHighUAllBins','noOutliers','verdict']
    w = csv.DictWriter(fh, fieldnames=fieldnames)
    w.writeheader(); w.writerows(rows)

print(f'[0308-consolidated] strict report={report}')
for r in rows:
    print('[0308-consolidated] strict', r['caseName'], r['modeName'], 'requested=', r['requestedSteps'], 'last=', r['lastDiagnosticStep'], 'wrapperRc=', r['wrapperRc'], 'highU=', r['sumHighUAllBins'], 'verdict=', r['verdict'])
if not overall_ok:
    raise SystemExit(3)
PYSTRICT
fi

if [[ "$rc" != "0" ]]; then
  echo "[0308-consolidated] FAIL rc=$rc" >&2
  exit "$rc"
fi

echo "[0308-consolidated] PASS"
echo "[0308-consolidated] per-run=$ART_DIR/cuda_resampling_split_safety_consolidated_0308_per_run.csv"
echo "[0308-consolidated] worst=$ART_DIR/cuda_resampling_split_safety_consolidated_0308_worst_cells.csv"
echo "[0308-consolidated] strict=$STRICT_REPORT"
