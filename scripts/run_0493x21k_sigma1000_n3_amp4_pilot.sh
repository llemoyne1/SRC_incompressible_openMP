#!/usr/bin/env bash
# 0493x21k — sigma=1000, n=3, amplitude=4h linearity/SNR pilot.
#
# Purpose: determine whether the sigma=1000 qualification failure at amplitude
# 2h is caused by insufficient signal-to-noise.  Physics, binary, analyzer,
# fit windows and qualification thresholds remain unchanged.  Only the initial
# capillary-wave amplitude changes from 2h to 4h.
#
# This runner deliberately tests ONLY n=3 with the original three article seeds.
# It does not automatically launch n=2/n=4 even if PASS; the amplitude-linearity
# diagnostic must be inspected first.

ROOT="${ROOT:-/mnt/e/SRC_MPCD_DEV/SRC_GPU-SURF}"
cd "$ROOT" || { echo "[x21k] ERROR cannot cd to $ROOT" >&2; exit 2; }

BASE_RUNNER="$ROOT/scripts/run_0493x12cal_capillary_calibrator.sh"
ANALYZER="$ROOT/scripts/analyze_0493x12cal_capillary_calibrator.py"
GENERATOR="$ROOT/scripts/generate_0493x11b_capillary_wave_state.py"
BIN="$ROOT/build/src_mpcd_base_cuda_q6_resident_livevis_0486"
EXPECTED_BIN_SHA256="422a199e0bdd2ae0525f41a332299cabec268fee7d04957d839e1e765a806ecc"

SIGMA_TEST=1000
AMPLITUDE_TEST=4.0
SEED1=4932501
SEED2=4933501
SEED3=4934501
SEEDS="$SEED1 $SEED2 $SEED3"

CASE_BASE="${CASE_BASE:-runs/0493x21k_article_capillary_sigma1000_n3_amp4}"
ENSEMBLE_ROOT="${ENSEMBLE_ROOT:-runs/0493x21k_article_capillary_sigma1000_n3_amp4_ensemble}"
MANIFEST="$ENSEMBLE_ROOT/manifest_0493x12cal.csv"
ANALYSIS="$ENSEMBLE_ROOT/analysis"
GATE="$ANALYSIS/ensemble_gate_0493x21k_sigma1000_n3_amp4_3seeds.txt"
LINEARITY="$ANALYSIS/amplitude_linearity_0493x21k.txt"
BASELINE_A2="${BASELINE_A2:-runs/0493x21i_article_capillary_sigma1000_n3_ensemble/analysis/capillary_calibration_modes_0493x12cal.csv}"

PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
ANALYZE_ONLY="${ANALYZE_ONLY:-0}"
RESTART="${RESTART:-1}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"

die() { echo "[x21k] ERROR $*" >&2; exit 2; }

for f in "$BASE_RUNNER" "$ANALYZER" "$GENERATOR" "$BIN"; do
  [[ -f "$f" ]] || die "missing required file: $f"
done
[[ -x "$BIN" ]] || die "binary is not executable: $BIN"
actual_sha="$(sha256sum "$BIN" | awk '{print $1}')"
[[ "$actual_sha" == "$EXPECTED_BIN_SHA256" ]] || \
  die "binary SHA mismatch: expected=$EXPECTED_BIN_SHA256 actual=$actual_sha; no rebuild allowed"

# Same orchestration-only x12cal derivative used by x21f/x21g/x21i.
tmp_runner="$(mktemp /tmp/run_0493x21k_x12cal_XXXXXX.sh)" || die "mktemp failed"
cleanup() { rm -f "$tmp_runner"; }
trap cleanup EXIT
python3 - "$BASE_RUNNER" "$tmp_runner" <<'PY' || exit 2
from pathlib import Path
import sys
src=Path(sys.argv[1]).read_text(encoding='utf-8')
old='PROJECTION_MOMENTUM_CORRECTION_ENABLE=true'
if src.count(old)!=1:
    raise SystemExit(f"[x21k] expected exactly one '{old}', found {src.count(old)}")
src=src.replace(old,'PROJECTION_MOMENTUM_CORRECTION_ENABLE=false',1)
needle='Q6_STRICT=1'
if needle not in src:
    raise SystemExit('[x21k] Q6_STRICT=1 anchor not found')
if 'Q6_FORCE_PROJECTION_MODE=prestream_single_fused' not in src:
    src=src.replace(needle,needle+'\nQ6_FORCE_PROJECTION_MODE=prestream_single_fused',1)
Path(sys.argv[2]).write_text(src,encoding='utf-8')
PY
chmod 700 "$tmp_runner" || die "cannot chmod temporary runner"

# Exact article fluid and x13h production chain.  ONLY amplitude differs from x21i.
export BIN LIVE_PROGRESS
export PROFILE=production
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

export SIGMA_DECLARED="$SIGMA_TEST"
export MEAN_HEIGHT=0.25
export AMPLITUDE_CELLS="$AMPLITUDE_TEST"
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
export LIVE_VIS_ENABLE=0

case_root() { printf '%s_seed%s' "$CASE_BASE" "$1"; }
case_manifest() { printf '%s/manifest_0493x12cal.csv' "$(case_root "$1")"; }

validate_case() {
  local seed="$1" manifest
  manifest="$(case_manifest "$seed")"
  [[ -s "$manifest" ]] || return 1
  python3 - "$manifest" "$seed" "$SIGMA_TEST" "$AMPLITUDE_TEST" <<'PY'
import csv,math,sys
from pathlib import Path
p=Path(sys.argv[1]); seed=int(sys.argv[2]); sigma=float(sys.argv[3]); amp=float(sys.argv[4])
with p.open(newline='') as f: rows=list(csv.DictReader(f))
if len(rows)!=1: raise SystemExit(1)
r=rows[0]
checks={'mode':3.0,'seed':float(seed),'sigma_declared':sigma,'Lx':1.0,'Ly':0.5,
        'nx':256.0,'ny':128.0,'h':1.0/256.0,'gamma':8.0,'liquid_mass':1.0,
        'kBT':0.125,'mean_height':0.25,'amplitude_cells':amp,
        'min_radius_cells':4.0,'x12a_radius_cells':25.298221281347036}
for k,v in checks.items():
    try: got=float(r[k])
    except Exception: raise SystemExit(1)
    if not math.isclose(got,v,rel_tol=1e-12,abs_tol=1e-14): raise SystemExit(1)
if r.get('calibration_path','')!='src-q6-g-f': raise SystemExit(1)
run_dir=Path(r['run_dir'])
if not list((run_dir/'output'/'recordings').rglob('timeline.csv')): raise SystemExit(1)
mode_csv=p.parent/'analysis'/'capillary_calibration_modes_0493x12cal.csv'
if not mode_csv.is_file() or mode_csv.stat().st_size==0: raise SystemExit(1)
PY
}

run_case() {
  local seed="$1" root
  root="$(case_root "$seed")"
  if [[ "$ANALYZE_ONLY" == 1 ]]; then
    validate_case "$seed" || die "ANALYZE_ONLY requires complete seed=$seed"
    echo "[x21k] ANALYZE_ONLY reuse seed=$seed root=$root"
    return 0
  fi
  if [[ "$RESTART" == 1 ]] && validate_case "$seed"; then
    echo "[x21k] RESTART reuse complete seed=$seed root=$root"
    return 0
  fi
  export MODES=3 BASE_SEED="$seed" RUN_ROOT="$root" CLEAN_RUN_ROOT=1 PREFLIGHT_ONLY=0 ANALYZE_ONLY=0
  echo
  echo "===== 0493x21k sigma=1000 n=3 amplitude=4h ====="
  echo "seed=$seed amplitudeCells=$AMPLITUDE_CELLS binarySHA256=$actual_sha"
  ROOT="$ROOT" bash "$tmp_runner" || die "run/analyze failed seed=$seed"
  validate_case "$seed" || die "completed case failed identity/completeness check seed=$seed"
}

combine_manifests() {
  python3 - "$MANIFEST" "$SIGMA_TEST" "$AMPLITUDE_TEST" "$(case_manifest "$SEED1")" "$(case_manifest "$SEED2")" "$(case_manifest "$SEED3")" <<'PY'
import csv,math,sys
from pathlib import Path
out=Path(sys.argv[1]); sigma=float(sys.argv[2]); amp=float(sys.argv[3]); paths=[Path(x) for x in sys.argv[4:]]
rows=[]
for p in paths:
    with p.open(newline='') as f: rr=list(csv.DictReader(f))
    if len(rr)!=1: raise SystemExit(f'[x21k] expected one row in {p}')
    rows+=rr
fields=list(rows[0].keys())
expected={(3,s) for s in (4932501,4933501,4934501)}
seen={(int(float(r['mode'])),int(float(r['seed']))) for r in rows}
if seen!=expected: raise SystemExit(f'[x21k] seed matrix mismatch {seen}')
for r in rows:
    if not math.isclose(float(r['sigma_declared']),sigma,rel_tol=1e-12,abs_tol=1e-14): raise SystemExit('[x21k] sigma mismatch')
    if not math.isclose(float(r['amplitude_cells']),amp,rel_tol=1e-12,abs_tol=1e-14): raise SystemExit('[x21k] amplitude mismatch')
rows.sort(key=lambda r:int(float(r['seed'])))
out.parent.mkdir(parents=True,exist_ok=True)
with out.open('w',newline='') as f:
    w=csv.DictWriter(f,fieldnames=fields); w.writeheader(); w.writerows(rows)
print(f'[x21k] combined manifest={out} rows={len(rows)}')
PY
}

analyze() {
  mkdir -p "$ANALYSIS" || die "cannot create $ANALYSIS"
  python3 "$ANALYZER" --manifest "$MANIFEST" --output-dir "$ANALYSIS" \
    --fit-periods 1.0 --sensitivity-periods 0.75,1.0,1.25 \
    --characteristic-U -1 --characteristic-D -1 \
    --kinematic-viscosity 0.00051019788 --gravity 0 || die "x12cal analysis failed"
}

if [[ "$PREFLIGHT_ONLY" == 1 ]]; then
  export MODES=3 BASE_SEED="$SEED1" RUN_ROOT="$(case_root "$SEED1")" CLEAN_RUN_ROOT=1 PREFLIGHT_ONLY=1 ANALYZE_ONLY=0
  echo "===== 0493x21k PREFLIGHT sigma=1000 n=3 amplitude=4h ====="
  echo "a/lambda=0.046875; k*a=0.294524311274; unchanged fit windows/thresholds"
  echo "binarySHA256=$actual_sha"
  ROOT="$ROOT" bash "$tmp_runner" || die "preflight failed"
  echo "[x21k] PREFLIGHT_ONLY complete; no simulation launched."
  exit 0
fi

for seed in $SEEDS; do run_case "$seed"; done
combine_manifests
analyze

MODE_CSV="$ANALYSIS/capillary_calibration_modes_0493x12cal.csv"
[[ -s "$MODE_CSV" ]] || die "missing mode CSV: $MODE_CSV"
python3 - "$MODE_CSV" "$GATE" <<'PY'
import csv,sys
from pathlib import Path
with Path(sys.argv[1]).open(newline='') as f: rows=list(csv.DictReader(f))
if len(rows)!=1: raise SystemExit(f'[x21k] expected one mode row, found {len(rows)}')
r=rows[0]; om=float(r['omegaFitEnsemble']); th=float(r['omegaTheoryDeclared'])
lines=[
 '===== 0493x21k sigma=1000 n=3 amplitude=4h THREE-SEED GATE =====',
 f"ENSEMBLE_GATE={r['status']}", 'sigmaDeclared=1000', 'mode=3', 'amplitudeCells=4',
 'aOverLambda=0.046875', 'ka=0.294524311274', 'seeds=4932501,4933501,4934501',
 f'omegaFit={om:.12g}', f'omegaTheoryDeclared={th:.12g}', f'omegaFitOverTheory={om/th:.12g}',
 f"fitR2={float(r['fitR2Ensemble']):.12g}", f"windowGainStd={float(r['windowGainStd']):.12g}",
 f"windowGainMin={float(r['windowGainMin']):.12g}", f"windowGainMax={float(r['windowGainMax']):.12g}",
 f"Gsigma={float(r['surfaceTensionGainEnsemble']):.12g}", f"sigmaEffRaw={float(r['sigmaEffectiveEnsemble']):.12g}",
 f"seedGainMean={float(r['seedGainMean']):.12g}", f"seedGainStd={float(r['seedGainStd']):.12g}",
 f"snrStartProxyEnsemble={float(r['snrStartProxyEnsemble']):.12g}",
 'policy=unchanged x12cal thresholds; amplitude increase is diagnostic only.',
 'next=inspect amplitude linearity before any n=2/n=4 extension even if PASS.'
]
Path(sys.argv[2]).write_text('\n'.join(lines)+'\n',encoding='utf-8')
print('\n'.join(lines))
PY

# Non-gating same-seed amplitude-linearity comparison against x21i amplitude=2h.
if [[ -s "$BASELINE_A2" ]]; then
  python3 - "$BASELINE_A2" "$MODE_CSV" "$LINEARITY" <<'PY' || true
import csv,math,sys
from pathlib import Path
def one(p):
    with Path(p).open(newline='') as f: rr=list(csv.DictReader(f))
    if len(rr)!=1: raise RuntimeError(f'expected one row in {p}')
    return rr[0]
a=one(sys.argv[1]); b=one(sys.argv[2])
om2=float(a['omegaFitEnsemble']); om4=float(b['omegaFitEnsemble'])
g2=float(a['surfaceTensionGainEnsemble']); g4=float(b['surfaceTensionGainEnsemble'])
w2=float(a['windowGainStd']); w4=float(b['windowGainStd'])
s2=float(a['snrStartProxyEnsemble']); s4=float(b['snrStartProxyEnsemble'])
lines=[
 '===== 0493x21k AMPLITUDE LINEARITY DIAGNOSTIC (NON-GATING) =====',
 'sigmaDeclared=1000', 'mode=3', 'sameSeeds=4932501,4933501,4934501',
 f'omegaAmp2={om2:.12g}', f'omegaAmp4={om4:.12g}', f'omegaAmp4OverAmp2={om4/om2:.12g}',
 f'omegaRelativeChange={(om4-om2)/om2:.12g}', f'GsigmaAmp2={g2:.12g}', f'GsigmaAmp4={g4:.12g}',
 f'windowGainStdAmp2={w2:.12g}', f'windowGainStdAmp4={w4:.12g}',
 f'snrStartAmp2={s2:.12g}', f'snrStartAmp4={s4:.12g}', f'snrRatioAmp4OverAmp2={s4/s2:.12g}',
 'note=this comparison is descriptive only; no amplitude-linearity threshold is introduced post hoc.'
]
Path(sys.argv[3]).write_text('\n'.join(lines)+'\n',encoding='utf-8')
print('\n'.join(lines))
PY
else
  echo "[x21k] amplitude=2h baseline not found; linearity diagnostic skipped: $BASELINE_A2"
fi

echo
echo "[x21k] COMPLETE"
echo "[x21k] gate=$GATE"
echo "[x21k] linearity diagnostic=$LINEARITY"
echo "[x21k] mode CSV=$MODE_CSV"
