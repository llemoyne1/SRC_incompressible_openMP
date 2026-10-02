#!/usr/bin/env bash
# 0493x21g — complete the article capillary-wave campaign with n=2 and n=4,
# using the same three seeds already qualified for n=3, then perform the
# global n=2,3,4 three-seed calibration with the unchanged x12cal analyzer.
#
# Article orchestration only:
#   - no C++/CUDA source modification;
#   - no rebuild;
#   - no change to the qualified physical chain;
#   - no change to x12cal fit definitions or qualification thresholds.

ROOT="${ROOT:-/mnt/e/SRC_MPCD_DEV/SRC_GPU-SURF}"
cd "$ROOT" || { echo "[x21g] ERROR cannot cd to $ROOT" >&2; exit 2; }

BASE_RUNNER="$ROOT/scripts/run_0493x12cal_capillary_calibrator.sh"
ANALYZER="$ROOT/scripts/analyze_0493x12cal_capillary_calibrator.py"
GENERATOR="$ROOT/scripts/generate_0493x11b_capillary_wave_state.py"
BIN="$ROOT/build/src_mpcd_base_cuda_q6_resident_livevis_0486"
EXPECTED_BIN_SHA256="422a199e0bdd2ae0525f41a332299cabec268fee7d04957d839e1e765a806ecc"

N3_ROOT="${N3_ROOT:-runs/0493x21f_article_capillary_wave_n3_ensemble_seed4932501_4933501_4934501}"
N3_MANIFEST="$N3_ROOT/manifest_0493x12cal.csv"
N3_GATE="${N3_GATE:-$N3_ROOT/analysis/ensemble_gate_0493x21f_n3_3seeds.txt}"

SEED1=4932501
SEED2=4933501
SEED3=4934501
SEEDS="$SEED1 $SEED2 $SEED3"

RUN_BASE="${RUN_BASE:-runs/0493x21g_article_capillary_wave_n2_n4}"
GLOBAL_ROOT="${GLOBAL_ROOT:-runs/0493x21g_article_capillary_wave_n234_ensemble_seed4932501_4933501_4934501}"
GLOBAL_MANIFEST="$GLOBAL_ROOT/manifest_0493x12cal.csv"
GLOBAL_ANALYSIS="$GLOBAL_ROOT/analysis"
GLOBAL_GATE="$GLOBAL_ANALYSIS/global_gate_0493x21g_n234_3seeds.txt"

PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
ANALYZE_ONLY="${ANALYZE_ONLY:-0}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"

die() { echo "[x21g] ERROR $*" >&2; exit 2; }

for f in "$BASE_RUNNER" "$ANALYZER" "$GENERATOR" "$BIN"; do
  [[ -f "$f" ]] || die "missing required file: $f"
done
[[ -x "$BIN" ]] || die "binary is not executable: $BIN"
[[ -s "$N3_MANIFEST" ]] || die "qualified n=3 ensemble manifest missing: $N3_MANIFEST"
[[ -s "$N3_GATE" ]] || die "qualified n=3 gate missing: $N3_GATE"

grep -q '^ENSEMBLE_GATE=PASS$' "$N3_GATE" || die "n=3 ensemble gate is not PASS: $N3_GATE"

actual_sha="$(sha256sum "$BIN" | awk '{print $1}')"
[[ "$actual_sha" == "$EXPECTED_BIN_SHA256" ]] || \
  die "binary SHA mismatch: expected=$EXPECTED_BIN_SHA256 actual=$actual_sha; no rebuild allowed"

# Validate the existing n=3 reference before producing any new realization.
python3 - "$N3_MANIFEST" <<'PY' || exit 2
import csv, math, sys
from pathlib import Path
p = Path(sys.argv[1])
with p.open(newline='') as f:
    rows = list(csv.DictReader(f))
if len(rows) != 3:
    raise SystemExit(f"[x21g] expected 3 rows in n=3 manifest, found {len(rows)}")
expected = {(3, 4932501), (3, 4933501), (3, 4934501)}
seen = {(int(float(r['mode'])), int(float(r['seed']))) for r in rows}
if seen != expected:
    raise SystemExit(f"[x21g] unexpected n=3 mode/seed set: {sorted(seen)}")
checks = {
    'sigma_declared': 10000.0,
    'Lx': 1.0,
    'Ly': 0.5,
    'nx': 256.0,
    'ny': 128.0,
    'h': 1.0/256.0,
    'gamma': 8.0,
    'liquid_mass': 1.0,
    'kBT': 0.125,
    'mean_height': 0.25,
    'amplitude_cells': 2.0,
    'min_radius_cells': 4.0,
    'x12a_radius_cells': 25.298221281347036,
}
for r in rows:
    if r.get('calibration_path','') != 'src-q6-g-f':
        raise SystemExit(f"[x21g] n=3 calibration_path mismatch: {r.get('calibration_path','')}")
    for k,v in checks.items():
        got = float(r[k])
        if not math.isclose(got, v, rel_tol=1e-12, abs_tol=1e-14):
            raise SystemExit(f"[x21g] n=3 manifest mismatch {k}: got={got} expected={v}")
print('[x21g] qualified n=3 manifest identity PASS')
PY

# Temporary derivative of x12cal. This reproduces exactly the two orchestration
# adjustments already used by x21f, while leaving the historical x12cal runner
# untouched on disk.
tmp_runner="$(mktemp /tmp/run_0493x21g_x12cal_XXXXXX.sh)" || die "mktemp failed"
cleanup() { rm -f "$tmp_runner"; }
trap cleanup EXIT
python3 - "$BASE_RUNNER" "$tmp_runner" <<'PY' || exit 2
from pathlib import Path
import sys
src = Path(sys.argv[1]).read_text(encoding='utf-8')
old = 'PROJECTION_MOMENTUM_CORRECTION_ENABLE=true'
if src.count(old) != 1:
    raise SystemExit(f"[x21g] expected exactly one '{old}', found {src.count(old)}")
src = src.replace(old, 'PROJECTION_MOMENTUM_CORRECTION_ENABLE=false', 1)
needle = 'Q6_STRICT=1'
if needle not in src:
    raise SystemExit('[x21g] Q6_STRICT=1 anchor not found')
if 'Q6_FORCE_PROJECTION_MODE=prestream_single_fused' not in src:
    src = src.replace(needle, needle + '\nQ6_FORCE_PROJECTION_MODE=prestream_single_fused', 1)
Path(sys.argv[2]).write_text(src, encoding='utf-8')
PY
chmod 700 "$tmp_runner" || die "cannot chmod temporary runner"

# Exact nominal article fluid and qualified free-surface chain, copied from x21f.
export BIN
export LIVE_PROGRESS
export PROFILE=production
export MODES="2 4"
export REPLICATES=1
export RUN_PERIODS=2.0
export SAMPLES_PER_PERIOD=80
export FIT_PERIODS=1.0
export SENSITIVITY_PERIODS=0.75,1.0,1.25

export NX=256 NY=128 Lx=1.0 Ly=0.5
export GAMMA=8
export DT=0.0063471328149122585
export KBT=0.125
export LIQUID_TYPE=1
export LIQUID_MASS=1.0
export ROTATION_ANGLE=2.0943951023931953
export RANDOM_ROTATION_SIGN=true
export GRID_SHIFT_ENABLE=true
export THERMOSTAT_ENABLE=true
export THERMOSTAT_MODE=cell_relative_rescale
export THERMOSTAT_EVERY=1
export THERMOSTAT_TARGET_KBT=0.125
export THERMOSTAT_MIN_PARTICLES=3

export SIGMA_DECLARED=10000
export MEAN_HEIGHT=0.25
export AMPLITUDE_CELLS=2.0
export SURFACE_TENSION_MIN_RADIUS_CELLS=4
export MPCD_X12A_LOCAL_THERMAL_RADIUS_CELLS=25.298221281347036
export MPCD_X10O_THERMAL_SIGMAS=3.0
export MPCD_X10O_THERMAL_MAX_CELLS=0.75
export MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE_NORMAL_ONLY=0
export MPCD_X10_KINETIC_INTERFACE_FREE_CROSSING_CELLS=0.0
export MPCD_X13R_INTERFACE_CELL_COOLING=0
export MPCD_X13S_INTERFACE_ANISOTROPIC_COOLING=0
export MPCD_X13T_UNIFIED_PROGRESSIVE_INTERFACE_COOLING=0
export MPCD_X13W_ESCAPE_RESEED=0

export SEED_STRIDE=1000
export KINEMATIC_VISCOSITY=0.00051019788
export CHARACTERISTIC_U=-1
export CHARACTERISTIC_D=-1
export GRAVITY_MAGNITUDE=0

# These calibration runs are only 114--323 steps on a 256x128 grid.  Keep the
# recorder exactly as in x21f and do not open the GUI; this falls under the
# short/small-grid exception and preserves strict comparability with n=3.
export LIVE_VIS_ENABLE=0
export CLEAN_RUN_ROOT=1

case_root() {
  local seed="$1"
  printf '%s_seed%s' "$RUN_BASE" "$seed"
}

if [[ "$PREFLIGHT_ONLY" == 1 ]]; then
  export BASE_SEED="$SEED1"
  export RUN_ROOT="$(case_root "$SEED1")"
  export PREFLIGHT_ONLY=1
  export ANALYZE_ONLY=0
  echo "===== 0493x21g PREFLIGHT n=2,n=4 ====="
  echo "seeds=$SEED1,$SEED2,$SEED3"
  echo "binarySHA256=$actual_sha"
  ROOT="$ROOT" bash "$tmp_runner" || die "preflight failed"
  echo "[x21g] PREFLIGHT_ONLY complete; no simulation launched."
  exit 0
fi

if [[ "$ANALYZE_ONLY" != 1 ]]; then
  for seed in $SEEDS; do
    export BASE_SEED="$seed"
    export RUN_ROOT="$(case_root "$seed")"
    export PREFLIGHT_ONLY=0
    export ANALYZE_ONLY=0
    echo
    echo "===== 0493x21g ARTICLE CAPILLARY MODES n=2,n=4 ====="
    echo "seed=$seed modes=2,4"
    echo "binarySHA256=$actual_sha"
    echo "runRoot=$RUN_ROOT"
    ROOT="$ROOT" bash "$tmp_runner" || die "n=2,n=4 run/analyze failed for seed=$seed"
  done
fi

# Collect the three new two-mode manifests and the already-qualified n=3
# three-seed manifest into one nine-realization global manifest.
SEED1_MANIFEST="$(case_root "$SEED1")/manifest_0493x12cal.csv"
SEED2_MANIFEST="$(case_root "$SEED2")/manifest_0493x12cal.csv"
SEED3_MANIFEST="$(case_root "$SEED3")/manifest_0493x12cal.csv"
for f in "$SEED1_MANIFEST" "$SEED2_MANIFEST" "$SEED3_MANIFEST"; do
  [[ -s "$f" ]] || die "required n=2,n=4 manifest missing: $f"
done

mkdir -p "$GLOBAL_ANALYSIS" || die "cannot create global analysis directory"
python3 - "$N3_MANIFEST" "$SEED1_MANIFEST" "$SEED2_MANIFEST" "$SEED3_MANIFEST" "$GLOBAL_MANIFEST" <<'PY' || exit 2
import csv, math, sys
from pathlib import Path
n3p, p1, p2, p3, out = map(Path, sys.argv[1:])

def read_rows(p):
    with p.open(newline='') as f:
        rows = list(csv.DictReader(f))
    if not rows:
        raise SystemExit(f"[x21g] empty manifest: {p}")
    return rows

n3 = read_rows(n3p)
new_groups = [read_rows(p) for p in (p1,p2,p3)]
if len(n3) != 3:
    raise SystemExit(f"[x21g] expected 3 n=3 rows, found {len(n3)}")
for p, rows in zip((p1,p2,p3), new_groups):
    if len(rows) != 2:
        raise SystemExit(f"[x21g] expected 2 rows (n=2,n=4) in {p}, found {len(rows)}")

rows = n3 + [r for group in new_groups for r in group]
fields = list(rows[0].keys())
if any(list(r.keys()) != fields for r in rows[1:]):
    raise SystemExit('[x21g] manifest schemas differ')

expected = {(mode, seed) for mode in (2,3,4) for seed in (4932501,4933501,4934501)}
seen = {(int(float(r['mode'])), int(float(r['seed']))) for r in rows}
if seen != expected or len(rows) != 9:
    raise SystemExit(f"[x21g] global mode/seed matrix mismatch: {sorted(seen)}")

# Require all physical/configuration fields that must be common across modes.
keys = (
    'sigma_declared','Lx','Ly','nx','ny','h','gamma','liquid_mass','kBT',
    'mean_height','amplitude_cells','min_radius_cells','calibration_path','x12a_radius_cells'
)
base = rows[0]
for r in rows[1:]:
    for k in keys:
        a, b = base[k], r[k]
        if a == b:
            continue
        try:
            same = math.isclose(float(a), float(b), rel_tol=1e-12, abs_tol=1e-14)
        except Exception:
            same = False
        if not same:
            raise SystemExit(f"[x21g] incompatible global manifests at {k}: {a} vs {b}")

# Stable article ordering: mode first, then seed.
rows.sort(key=lambda r: (int(float(r['mode'])), int(float(r['seed']))))
out.parent.mkdir(parents=True, exist_ok=True)
with out.open('w', newline='') as f:
    w = csv.DictWriter(f, fieldnames=fields)
    w.writeheader(); w.writerows(rows)
print(f"[x21g] global manifest={out} rows={len(rows)}")
PY

python3 "$ANALYZER" \
  --manifest "$GLOBAL_MANIFEST" \
  --output-dir "$GLOBAL_ANALYSIS" \
  --fit-periods 1.0 \
  --sensitivity-periods 0.75,1.0,1.25 \
  --characteristic-U -1 \
  --characteristic-D -1 \
  --kinematic-viscosity 0.00051019788 \
  --gravity 0 || die "global n=2,3,4 analysis failed"

MODE_CSV="$GLOBAL_ANALYSIS/capillary_calibration_modes_0493x12cal.csv"
GLOBAL_CSV="$GLOBAL_ANALYSIS/capillary_calibration_0493x12cal.csv"
[[ -s "$MODE_CSV" ]] || die "global mode CSV missing: $MODE_CSV"
[[ -s "$GLOBAL_CSV" ]] || die "global calibration CSV missing: $GLOBAL_CSV"

python3 - "$MODE_CSV" "$GLOBAL_CSV" "$GLOBAL_GATE" <<'PY' || exit 2
import csv, math, sys
from pathlib import Path
mode_path, global_path, gate_path = map(Path, sys.argv[1:])
with mode_path.open(newline='') as f:
    modes = list(csv.DictReader(f))
with global_path.open(newline='') as f:
    glob = list(csv.DictReader(f))
if len(modes) != 3:
    raise SystemExit(f"[x21g] expected 3 mode rows, found {len(modes)}")
if len(glob) != 1:
    raise SystemExit(f"[x21g] expected 1 global row, found {len(glob)}")
g = glob[0]
modes.sort(key=lambda r: int(float(r['mode'])))

lines = [
    '===== 0493x21g ARTICLE CAPILLARY GLOBAL GATE =====',
    f"GLOBAL_GATE={g['status']}",
    'modes=2,3,4',
    'seeds=4932501,4933501,4934501',
    'sigmaDeclared=10000',
]
for r in modes:
    n = int(float(r['mode']))
    lines += [
        f"mode{n}Status={r['status']}",
        f"mode{n}OmegaFit={float(r['omegaFitEnsemble']):.12g}",
        f"mode{n}OmegaTheory={float(r['omegaTheoryDeclared']):.12g}",
        f"mode{n}OmegaRatio={float(r['omegaFitEnsemble'])/float(r['omegaTheoryDeclared']):.12g}",
        f"mode{n}FitR2={float(r['fitR2Ensemble']):.12g}",
        f"mode{n}WindowGainStd={float(r['windowGainStd']):.12g}",
        f"mode{n}Gsigma={float(r['surfaceTensionGainEnsemble']):.12g}",
        f"mode{n}SigmaEffRaw={float(r['sigmaEffectiveEnsemble']):.12g}",
        f"mode{n}SeedGainStd={float(r['seedGainStd']):.12g}",
    ]

# The x12cal analyzer deliberately publishes surfaceTensionEffective only on PASS.
def val(name, default=''):
    return g.get(name, default)
lines += [
    f"GsigmaGlobalRaw={float(val('surfaceTensionGain')):.12g}",
    f"sigmaEffGlobalRaw={float(val('surfaceTensionEffectiveRaw')):.12g}",
    f"sigmaEffQualified={val('surfaceTensionEffective')}",
    f"modeGainMean={float(val('surfaceTensionGainModeMean')):.12g}",
    f"modeGainStd={float(val('surfaceTensionGainModeStd')):.12g}",
    f"crossModeRelativeStd={float(val('surfaceTensionGainModeRelativeStd')):.12g}",
    f"meanFitR2={float(val('meanFitR2')):.12g}",
    'qualification=PASS requires all three mode ensembles PASS, mean fit R2>=0.98, and cross-mode relative gain std<=0.05.',
    'next=if GLOBAL_GATE=PASS, generate article Figure 5/Table 3 from frozen final CSVs; otherwise diagnose only the failing mode without changing thresholds.',
]
gate_path.write_text('\n'.join(lines)+'\n', encoding='utf-8')
print('\n'.join(lines))
PY

echo
echo "[x21g] COMPLETE"
echo "[x21g] global gate=$GLOBAL_GATE"
echo "[x21g] global modes=$MODE_CSV"
echo "[x21g] global calibration=$GLOBAL_CSV"
