#!/usr/bin/env bash
# 0493x21j — sigma=1000 n=3 five-seed ensemble stabilization test.
# Reuse the three completed x21i cases, add two seeds, and refit with the
# unchanged x12cal analyzer. No solver-source, amplitude, fit-window, or
# qualification-threshold changes are made.

ROOT="${ROOT:-/mnt/e/SRC_MPCD_DEV/SRC_GPU-SURF}"
cd "$ROOT" || { echo "[x21j] ERROR cannot cd to $ROOT" >&2; exit 2; }

BASE_RUNNER="$ROOT/scripts/run_0493x12cal_capillary_calibrator.sh"
ANALYZER="$ROOT/scripts/analyze_0493x12cal_capillary_calibrator.py"
GENERATOR="$ROOT/scripts/generate_0493x11b_capillary_wave_state.py"
BIN="$ROOT/build/src_mpcd_base_cuda_q6_resident_livevis_0486"
EXPECTED_BIN_SHA256="422a199e0bdd2ae0525f41a332299cabec268fee7d04957d839e1e765a806ecc"

SIGMA_TEST=1000
OLD_SEEDS="4932501 4933501 4934501"
NEW_SEEDS="4935501 4936501"
ALL_SEEDS="4932501 4933501 4934501 4935501 4936501"

CASE_BASE="${CASE_BASE:-runs/0493x21i_article_capillary_sigma1000}"
ENSEMBLE_ROOT="${ENSEMBLE_ROOT:-runs/0493x21j_article_capillary_sigma1000_n3_5seeds}"
MANIFEST="$ENSEMBLE_ROOT/manifest_0493x12cal.csv"
ANALYSIS="$ENSEMBLE_ROOT/analysis"
GATE="$ANALYSIS/ensemble_gate_0493x21j_sigma1000_n3_5seeds.txt"
BASELINE_MODE_CSV="${BASELINE_MODE_CSV:-runs/0493x21g_article_capillary_wave_n234_ensemble_seed4932501_4933501_4934501/analysis/capillary_calibration_modes_0493x12cal.csv}"

PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
ANALYZE_ONLY="${ANALYZE_ONLY:-0}"
RESTART="${RESTART:-1}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"

die() { echo "[x21j] ERROR $*" >&2; exit 2; }
for f in "$BASE_RUNNER" "$ANALYZER" "$GENERATOR" "$BIN"; do [[ -f "$f" ]] || die "missing required file: $f"; done
[[ -x "$BIN" ]] || die "binary is not executable: $BIN"
actual_sha="$(sha256sum "$BIN" | awk '{print $1}')"
[[ "$actual_sha" == "$EXPECTED_BIN_SHA256" ]] || die "binary SHA mismatch: expected=$EXPECTED_BIN_SHA256 actual=$actual_sha; no rebuild allowed"

tmp_runner="$(mktemp /tmp/run_0493x21j_x12cal_XXXXXX.sh)" || die "mktemp failed"
cleanup() { rm -f "$tmp_runner"; }
trap cleanup EXIT
python3 - "$BASE_RUNNER" "$tmp_runner" <<'PYRUN'
from pathlib import Path
import sys
src=Path(sys.argv[1]).read_text(encoding='utf-8')
old='PROJECTION_MOMENTUM_CORRECTION_ENABLE=true'
if src.count(old)!=1:
    raise SystemExit(f"[x21j] expected exactly one '{old}', found {src.count(old)}")
src=src.replace(old,'PROJECTION_MOMENTUM_CORRECTION_ENABLE=false',1)
needle='Q6_STRICT=1'
if needle not in src:
    raise SystemExit('[x21j] Q6_STRICT=1 anchor not found')
if 'Q6_FORCE_PROJECTION_MODE=prestream_single_fused' not in src:
    src=src.replace(needle,needle+'\nQ6_FORCE_PROJECTION_MODE=prestream_single_fused',1)
Path(sys.argv[2]).write_text(src,encoding='utf-8')
PYRUN
chmod 700 "$tmp_runner" || die "cannot chmod temporary runner"

# Exact x21i physical/numerical state; no parameter changes.
export BIN LIVE_PROGRESS
export PROFILE=production REPLICATES=1 RUN_PERIODS=2.0 SAMPLES_PER_PERIOD=80
export FIT_PERIODS=1.0 SENSITIVITY_PERIODS=0.75,1.0,1.25
export NX=256 NY=128 Lx=1.0 Ly=0.5 GAMMA=8 DT=0.0063471328149122585 KBT=0.125
export LIQUID_TYPE=1 LIQUID_MASS=1.0 ROTATION_ANGLE=2.0943951023931953 RANDOM_ROTATION_SIGN=true GRID_SHIFT_ENABLE=true
export THERMOSTAT_ENABLE=true THERMOSTAT_MODE=cell_relative_rescale THERMOSTAT_EVERY=1 THERMOSTAT_TARGET_KBT=0.125 THERMOSTAT_MIN_PARTICLES=3
export SIGMA_DECLARED="$SIGMA_TEST" MEAN_HEIGHT=0.25 AMPLITUDE_CELLS=2.0 SURFACE_TENSION_MIN_RADIUS_CELLS=4
export MPCD_X12A_LOCAL_THERMAL_RADIUS_CELLS=25.298221281347036 MPCD_X10O_THERMAL_SIGMAS=3.0 MPCD_X10O_THERMAL_MAX_CELLS=0.75
export MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE_NORMAL_ONLY=0 MPCD_X10_KINETIC_INTERFACE_FREE_CROSSING_CELLS=0.0
export MPCD_X13R_INTERFACE_CELL_COOLING=0 MPCD_X13S_INTERFACE_ANISOTROPIC_COOLING=0 MPCD_X13T_UNIFIED_PROGRESSIVE_INTERFACE_COOLING=0 MPCD_X13W_ESCAPE_RESEED=0
export SEED_STRIDE=1000 KINEMATIC_VISCOSITY=0.00051019788 CHARACTERISTIC_U=-1 CHARACTERISTIC_D=-1 GRAVITY_MAGNITUDE=0 LIVE_VIS_ENABLE=0

case_root() { printf '%s_n%s_seed%s' "$CASE_BASE" "$1" "$2"; }
case_manifest() { printf '%s/manifest_0493x12cal.csv' "$(case_root "$1" "$2")"; }

validate_case() {
  local mode="$1" seed="$2" manifest
  manifest="$(case_manifest "$mode" "$seed")"
  [[ -s "$manifest" ]] || return 1
  python3 - "$manifest" "$mode" "$seed" <<'PY1'
import csv,math,sys
from pathlib import Path
p=Path(sys.argv[1]); mode=int(sys.argv[2]); seed=int(sys.argv[3])
with p.open(newline='') as f: rr=list(csv.DictReader(f))
if len(rr)!=1: raise SystemExit(1)
r=rr[0]
checks={'mode':mode,'seed':seed,'sigma_declared':1000.0,'Lx':1.0,'Ly':0.5,'nx':256.0,'ny':128.0,'h':1/256,'gamma':8.0,'liquid_mass':1.0,'kBT':0.125,'mean_height':0.25,'amplitude_cells':2.0,'min_radius_cells':4.0,'x12a_radius_cells':25.298221281347036}
for k,v in checks.items():
    try: got=float(r[k])
    except Exception: raise SystemExit(1)
    if not math.isclose(got,float(v),rel_tol=1e-12,abs_tol=1e-14): raise SystemExit(1)
if r.get('calibration_path','')!='src-q6-g-f': raise SystemExit(1)
run_dir=Path(r['run_dir'])
if not list((run_dir/'output'/'recordings').rglob('timeline.csv')): raise SystemExit(1)
mode_csv=p.parent/'analysis'/'capillary_calibration_modes_0493x12cal.csv'
if not mode_csv.is_file() or mode_csv.stat().st_size==0: raise SystemExit(1)
PY1
}

run_case() {
  local seed="$1" root
  root="$(case_root 3 "$seed")"
  if [[ "$ANALYZE_ONLY" == 1 ]]; then
    validate_case 3 "$seed" || die "ANALYZE_ONLY requires complete case seed=$seed"
    echo "[x21j] ANALYZE_ONLY reuse seed=$seed"
    return 0
  fi
  if [[ "$RESTART" == 1 ]] && validate_case 3 "$seed"; then
    echo "[x21j] RESTART reuse complete seed=$seed root=$root"
    return 0
  fi
  export MODES=3 BASE_SEED="$seed" RUN_ROOT="$root" CLEAN_RUN_ROOT=1 PREFLIGHT_ONLY=0 ANALYZE_ONLY=0
  echo "===== 0493x21j sigma=1000 n=3 additional seed=$seed ====="
  ROOT="$ROOT" bash "$tmp_runner" || die "run/analyze failed seed=$seed"
  validate_case 3 "$seed" || die "completed case failed identity/completeness check seed=$seed"
}

if [[ "$PREFLIGHT_ONLY" == 1 ]]; then
  export MODES=3 BASE_SEED=4935501 RUN_ROOT="$(case_root 3 4935501)" CLEAN_RUN_ROOT=1 PREFLIGHT_ONLY=1 ANALYZE_ONLY=0
  echo "===== 0493x21j PREFLIGHT ====="
  echo "sigma=1000 mode=3 amplitudeCells=2 newSeed=4935501 binarySHA256=$actual_sha"
  ROOT="$ROOT" bash "$tmp_runner" || die "preflight failed"
  echo "[x21j] PREFLIGHT_ONLY complete; no simulation launched."
  exit 0
fi

# Existing x21i seeds are mandatory and never silently recomputed here.
for seed in $OLD_SEEDS; do
  validate_case 3 "$seed" || die "missing/incompatible completed x21i seed=$seed; rerun x21i first"
  echo "[x21j] reuse x21i seed=$seed"
done
for seed in $NEW_SEEDS; do run_case "$seed"; done

python3 - "$MANIFEST" $ALL_SEEDS <<'PY2'
import csv,math,sys
from pathlib import Path
out=Path(sys.argv[1]); seeds=[int(x) for x in sys.argv[2:]]
base=Path('runs/0493x21i_article_capillary_sigma1000')
paths=[Path(f'{base}_n3_seed{s}/manifest_0493x12cal.csv') for s in seeds]
rows=[]
for p in paths:
    with p.open(newline='') as f: rr=list(csv.DictReader(f))
    if len(rr)!=1: raise SystemExit(f'[x21j] expected one row in {p}')
    rows+=rr
fields=list(rows[0].keys())
seen={int(float(r['seed'])) for r in rows}
if seen!=set(seeds): raise SystemExit(f'[x21j] seed mismatch seen={seen}')
keys=('mode','sigma_declared','Lx','Ly','nx','ny','h','gamma','liquid_mass','kBT','mean_height','amplitude_cells','min_radius_cells','calibration_path','x12a_radius_cells')
b=rows[0]
for r in rows:
    for k in keys:
        a,c=b[k],r[k]
        if a==c: continue
        try: same=math.isclose(float(a),float(c),rel_tol=1e-12,abs_tol=1e-14)
        except Exception: same=False
        if not same: raise SystemExit(f'[x21j] incompatible manifests at {k}: {a} vs {c}')
rows.sort(key=lambda r:int(float(r['seed'])))
out.parent.mkdir(parents=True,exist_ok=True)
with out.open('w',newline='') as f:
    w=csv.DictWriter(f,fieldnames=fields); w.writeheader(); w.writerows(rows)
print(f'[x21j] combined manifest={out} rows={len(rows)}')
PY2

mkdir -p "$ANALYSIS" || die "cannot create $ANALYSIS"
python3 "$ANALYZER" --manifest "$MANIFEST" --output-dir "$ANALYSIS" --fit-periods 1.0 --sensitivity-periods 0.75,1.0,1.25 --characteristic-U -1 --characteristic-D -1 --kinematic-viscosity 0.00051019788 --gravity 0 || die "x12cal analysis failed"

MODE_CSV="$ANALYSIS/capillary_calibration_modes_0493x12cal.csv"
[[ -s "$MODE_CSV" ]] || die "missing mode CSV $MODE_CSV"
python3 - "$MODE_CSV" "$GATE" "$BASELINE_MODE_CSV" <<'PY3'
import csv,math,sys
from pathlib import Path
mp,out,baseline=map(Path,sys.argv[1:])
with mp.open(newline='') as f: rr=list(csv.DictReader(f))
if len(rr)!=1: raise SystemExit('[x21j] expected one mode row')
r=rr[0]
om=float(r['omegaFitEnsemble']); th=float(r['omegaTheoryDeclared'])
lines=[
 '===== 0493x21j sigma=1000 n=3 FIVE-SEED ENSEMBLE GATE =====',
 f'ENSEMBLE_GATE={r["status"]}', 'sigmaDeclared=1000', 'mode=3',
 'seeds=4932501,4933501,4934501,4935501,4936501',
 f'omegaFit={om:.12g}', f'omegaTheoryDeclared={th:.12g}', f'omegaFitOverTheory={om/th:.12g}',
 f'fitR2={float(r["fitR2Ensemble"]):.12g}', f'windowGainStd={float(r["windowGainStd"]):.12g}',
 f'windowGainMin={float(r["windowGainMin"]):.12g}', f'windowGainMax={float(r["windowGainMax"]):.12g}',
 f'Gsigma={float(r["surfaceTensionGainEnsemble"]):.12g}', f'sigmaEffRaw={float(r["sigmaEffectiveEnsemble"]):.12g}',
 f'seedGainMean={float(r["seedGainMean"]):.12g}', f'seedGainStd={float(r["seedGainStd"]):.12g}',
 f'snrStartProxyEnsemble={float(r["snrStartProxyEnsemble"]):.12g}'
]
if baseline.is_file():
    with baseline.open(newline='') as f: br=list(csv.DictReader(f))
    b=next((x for x in br if int(float(x['mode']))==3),None)
    if b:
        oh=float(b['omegaFitEnsemble']); ratio=om/oh; ideal=math.sqrt(0.1)
        lines += [f'omegaSigma10000={oh:.12g}',f'omegaLowOverHigh={ratio:.12g}',f'idealSqrtSigmaRatio={ideal:.12g}',f'crossSigmaFrequencyRatioRelativeError={(ratio/ideal-1):.12g}']
lines += [
 'policy=unchanged x12cal thresholds; no threshold, amplitude, fit-window, or physics modification.',
 'next=if PASS, complete n=2 and n=4 at sigma=1000; if REVIEW/INVALID, do not claim qualified sigma_eff and diagnose damping/window sensitivity.'
]
out.write_text('\n'.join(lines)+'\n',encoding='utf-8')
print('\n'.join(lines))
PY3

echo "[x21j] COMPLETE gate=$GATE"
