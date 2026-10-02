#!/usr/bin/env bash
# 0493x21i — independent one-decade surface-tension validation at sigma=1000.
#
# Strategy:
#   1) run n=3 with the same three seeds as the sigma=10000 article campaign;
#   2) ensemble-fit n=3 with the unchanged x12cal analyzer;
#   3) only if the n=3 ensemble is PASS, automatically run n=2 and n=4;
#   4) ensemble-fit n=2,3,4 and apply the unchanged global x12cal gate.
#
# Article/qualification orchestration only:
#   - no C++/CUDA source modification;
#   - no rebuild;
#   - no change to the qualified x13h physical chain;
#   - no change to x12cal fit definitions or qualification thresholds;
#   - only sigmaDeclared changes from 10000 to 1000.
#
# RESTART=1 (default) reuses completed individual realizations.  Because these
# are small 256x128 calibrators, an interrupted realization itself is rerun;
# completed mode/seed cases are not recomputed.

ROOT="${ROOT:-/mnt/e/SRC_MPCD_DEV/SRC_GPU-SURF}"
cd "$ROOT" || { echo "[x21i] ERROR cannot cd to $ROOT" >&2; exit 2; }

BASE_RUNNER="$ROOT/scripts/run_0493x12cal_capillary_calibrator.sh"
ANALYZER="$ROOT/scripts/analyze_0493x12cal_capillary_calibrator.py"
GENERATOR="$ROOT/scripts/generate_0493x11b_capillary_wave_state.py"
BIN="$ROOT/build/src_mpcd_base_cuda_q6_resident_livevis_0486"
EXPECTED_BIN_SHA256="422a199e0bdd2ae0525f41a332299cabec268fee7d04957d839e1e765a806ecc"

SIGMA_TEST=1000
SEED1=4932501
SEED2=4933501
SEED3=4934501
SEEDS="$SEED1 $SEED2 $SEED3"

CASE_BASE="${CASE_BASE:-runs/0493x21i_article_capillary_sigma1000}"
PILOT_ROOT="${PILOT_ROOT:-runs/0493x21i_article_capillary_sigma1000_n3_ensemble}"
GLOBAL_ROOT="${GLOBAL_ROOT:-runs/0493x21i_article_capillary_sigma1000_n234_ensemble}"
PILOT_MANIFEST="$PILOT_ROOT/manifest_0493x12cal.csv"
PILOT_ANALYSIS="$PILOT_ROOT/analysis"
PILOT_GATE="$PILOT_ANALYSIS/pilot_gate_0493x21i_sigma1000_n3_3seeds.txt"
GLOBAL_MANIFEST="$GLOBAL_ROOT/manifest_0493x12cal.csv"
GLOBAL_ANALYSIS="$GLOBAL_ROOT/analysis"
GLOBAL_GATE="$GLOBAL_ANALYSIS/global_gate_0493x21i_sigma1000_n234_3seeds.txt"
CROSS_SIGMA="$GLOBAL_ANALYSIS/cross_sigma_comparison_0493x21i.txt"
BASELINE_GLOBAL="${BASELINE_GLOBAL:-runs/0493x21g_article_capillary_wave_n234_ensemble_seed4932501_4933501_4934501/analysis/capillary_calibration_0493x12cal.csv}"

PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
ANALYZE_ONLY="${ANALYZE_ONLY:-0}"
RESTART="${RESTART:-1}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"

die() { echo "[x21i] ERROR $*" >&2; exit 2; }

for f in "$BASE_RUNNER" "$ANALYZER" "$GENERATOR" "$BIN"; do
  [[ -f "$f" ]] || die "missing required file: $f"
done
[[ -x "$BIN" ]] || die "binary is not executable: $BIN"

actual_sha="$(sha256sum "$BIN" | awk '{print $1}')"
[[ "$actual_sha" == "$EXPECTED_BIN_SHA256" ]] || \
  die "binary SHA mismatch: expected=$EXPECTED_BIN_SHA256 actual=$actual_sha; no rebuild allowed"

# Temporary orchestration-only derivative of x12cal.  This is exactly the
# production adjustment already used by x21f/x21g; the historical runner on
# disk is not modified.
tmp_runner="$(mktemp /tmp/run_0493x21i_x12cal_XXXXXX.sh)" || die "mktemp failed"
cleanup() { rm -f "$tmp_runner"; }
trap cleanup EXIT
python3 - "$BASE_RUNNER" "$tmp_runner" <<'PY' || exit 2
from pathlib import Path
import sys
src = Path(sys.argv[1]).read_text(encoding='utf-8')
old = 'PROJECTION_MOMENTUM_CORRECTION_ENABLE=true'
if src.count(old) != 1:
    raise SystemExit(f"[x21i] expected exactly one '{old}', found {src.count(old)}")
src = src.replace(old, 'PROJECTION_MOMENTUM_CORRECTION_ENABLE=false', 1)
needle = 'Q6_STRICT=1'
if needle not in src:
    raise SystemExit('[x21i] Q6_STRICT=1 anchor not found')
if 'Q6_FORCE_PROJECTION_MODE=prestream_single_fused' not in src:
    src = src.replace(needle, needle + '\nQ6_FORCE_PROJECTION_MODE=prestream_single_fused', 1)
Path(sys.argv[2]).write_text(src, encoding='utf-8')
PY
chmod 700 "$tmp_runner" || die "cannot chmod temporary runner"

# Exact nominal article fluid / qualified x13h free-surface chain.
# Deliberately identical to x21g except SIGMA_DECLARED.
export BIN
export LIVE_PROGRESS
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

# Preserve strict comparability with x21f/x21g.  The mass recorder remains
# active inside x12cal; no GUI is opened for these small 256x128 calibrators.
export LIVE_VIS_ENABLE=0

case_root() {
  local mode="$1" seed="$2"
  printf '%s_n%s_seed%s' "$CASE_BASE" "$mode" "$seed"
}

case_manifest() {
  local mode="$1" seed="$2"
  printf '%s/manifest_0493x12cal.csv' "$(case_root "$mode" "$seed")"
}

validate_case() {
  local mode="$1" seed="$2" manifest
  manifest="$(case_manifest "$mode" "$seed")"
  [[ -s "$manifest" ]] || return 1
  python3 - "$manifest" "$mode" "$seed" "$SIGMA_TEST" <<'PY'
import csv, math, sys
from pathlib import Path
manifest=Path(sys.argv[1]); mode=int(sys.argv[2]); seed=int(sys.argv[3]); sigma=float(sys.argv[4])
with manifest.open(newline='') as f:
    rows=list(csv.DictReader(f))
if len(rows)!=1:
    raise SystemExit(1)
r=rows[0]
checks={
 'mode':float(mode), 'seed':float(seed), 'sigma_declared':sigma,
 'Lx':1.0, 'Ly':0.5, 'nx':256.0, 'ny':128.0, 'h':1.0/256.0,
 'gamma':8.0, 'liquid_mass':1.0, 'kBT':0.125, 'mean_height':0.25,
 'amplitude_cells':2.0, 'min_radius_cells':4.0,
 'x12a_radius_cells':25.298221281347036,
}
for k,v in checks.items():
    try: got=float(r[k])
    except Exception: raise SystemExit(1)
    if not math.isclose(got,v,rel_tol=1e-12,abs_tol=1e-14):
        raise SystemExit(1)
if r.get('calibration_path','')!='src-q6-g-f':
    raise SystemExit(1)
run_dir=Path(r['run_dir'])
timelines=list((run_dir/'output'/'recordings').rglob('timeline.csv'))
mode_csv=manifest.parent/'analysis'/'capillary_calibration_modes_0493x12cal.csv'
if not timelines or not mode_csv.is_file() or mode_csv.stat().st_size==0:
    raise SystemExit(1)
raise SystemExit(0)
PY
}

run_case() {
  local mode="$1" seed="$2" root
  root="$(case_root "$mode" "$seed")"

  if [[ "$ANALYZE_ONLY" == 1 ]]; then
    validate_case "$mode" "$seed" || die "ANALYZE_ONLY requires complete case mode=$mode seed=$seed"
    echo "[x21i] ANALYZE_ONLY reuse mode=$mode seed=$seed root=$root"
    return 0
  fi

  if [[ "$RESTART" == 1 ]] && validate_case "$mode" "$seed"; then
    echo "[x21i] RESTART reuse complete mode=$mode seed=$seed root=$root"
    return 0
  fi

  export MODES="$mode"
  export BASE_SEED="$seed"
  export RUN_ROOT="$root"
  export CLEAN_RUN_ROOT=1
  export PREFLIGHT_ONLY=0
  export ANALYZE_ONLY=0

  echo
  echo "===== 0493x21i sigma=1000 capillary wave ====="
  echo "mode=$mode seed=$seed amplitudeCells=$AMPLITUDE_CELLS"
  echo "binarySHA256=$actual_sha"
  echo "runRoot=$root"
  ROOT="$ROOT" bash "$tmp_runner" || die "run/analyze failed mode=$mode seed=$seed"
  validate_case "$mode" "$seed" || die "completed case failed identity/completeness check mode=$mode seed=$seed"
}

combine_manifests() {
  local output="$1" modes="$2"
  shift 2
  python3 - "$output" "$modes" "$SIGMA_TEST" "$@" <<'PY'
import csv, math, sys
from pathlib import Path
out=Path(sys.argv[1]); modes=[int(x) for x in sys.argv[2].split(',')]; sigma=float(sys.argv[3])
paths=[Path(x) for x in sys.argv[4:]]
rows=[]
for p in paths:
    with p.open(newline='') as f:
        rr=list(csv.DictReader(f))
    if len(rr)!=1:
        raise SystemExit(f"[x21i] expected one row in {p}, found {len(rr)}")
    rows += rr
if not rows:
    raise SystemExit('[x21i] no manifest rows')
fields=list(rows[0].keys())
if any(list(r.keys())!=fields for r in rows[1:]):
    raise SystemExit('[x21i] manifest schemas differ')
expected={(m,s) for m in modes for s in (4932501,4933501,4934501)}
seen={(int(float(r['mode'])),int(float(r['seed']))) for r in rows}
if seen!=expected or len(rows)!=len(expected):
    raise SystemExit(f"[x21i] mode/seed matrix mismatch expected={sorted(expected)} seen={sorted(seen)}")
keys=('sigma_declared','Lx','Ly','nx','ny','h','gamma','liquid_mass','kBT','mean_height','amplitude_cells','min_radius_cells','calibration_path','x12a_radius_cells')
base=rows[0]
for r in rows:
    if not math.isclose(float(r['sigma_declared']),sigma,rel_tol=1e-12,abs_tol=1e-14):
        raise SystemExit('[x21i] sigma mismatch')
    for k in keys:
        a,b=base[k],r[k]
        if a==b: continue
        try: same=math.isclose(float(a),float(b),rel_tol=1e-12,abs_tol=1e-14)
        except Exception: same=False
        if not same:
            raise SystemExit(f"[x21i] incompatible manifests at {k}: {a} vs {b}")
rows.sort(key=lambda r:(int(float(r['mode'])),int(float(r['seed']))))
out.parent.mkdir(parents=True,exist_ok=True)
with out.open('w',newline='') as f:
    w=csv.DictWriter(f,fieldnames=fields); w.writeheader(); w.writerows(rows)
print(f"[x21i] combined manifest={out} rows={len(rows)}")
PY
}

analyze_manifest() {
  local manifest="$1" outdir="$2"
  mkdir -p "$outdir" || die "cannot create analysis directory: $outdir"
  python3 "$ANALYZER" \
    --manifest "$manifest" \
    --output-dir "$outdir" \
    --fit-periods 1.0 \
    --sensitivity-periods 0.75,1.0,1.25 \
    --characteristic-U -1 \
    --characteristic-D -1 \
    --kinematic-viscosity 0.00051019788 \
    --gravity 0 || die "x12cal analysis failed for $manifest"
}

# Preflight only: exercise the exact sigma=1000/n=3 case without simulation.
if [[ "$PREFLIGHT_ONLY" == 1 ]]; then
  export MODES=3
  export BASE_SEED="$SEED1"
  export RUN_ROOT="$(case_root 3 "$SEED1")"
  export CLEAN_RUN_ROOT=1
  export PREFLIGHT_ONLY=1
  export ANALYZE_ONLY=0
  echo "===== 0493x21i PREFLIGHT sigma=1000 ====="
  echo "pilot mode=3 seed=$SEED1"
  echo "same amplitude=2h, same nominal article fluid, same x13h chain"
  echo "binarySHA256=$actual_sha"
  ROOT="$ROOT" bash "$tmp_runner" || die "preflight failed"
  echo "[x21i] PREFLIGHT_ONLY complete; no simulation launched."
  exit 0
fi

# ---------------------------------------------------------------------------
# Stage 1: fast three-seed n=3 gate.
# ---------------------------------------------------------------------------
for seed in $SEEDS; do
  run_case 3 "$seed"
done

pilot_inputs=""
for seed in $SEEDS; do pilot_inputs="$pilot_inputs $(case_manifest 3 "$seed")"; done
# shellcheck disable=SC2086
combine_manifests "$PILOT_MANIFEST" "3" $pilot_inputs || die "cannot assemble n=3 pilot manifest"
analyze_manifest "$PILOT_MANIFEST" "$PILOT_ANALYSIS"

PILOT_MODE_CSV="$PILOT_ANALYSIS/capillary_calibration_modes_0493x12cal.csv"
[[ -s "$PILOT_MODE_CSV" ]] || die "pilot mode CSV missing: $PILOT_MODE_CSV"
python3 - "$PILOT_MODE_CSV" "$PILOT_GATE" <<'PY' || exit 2
import csv, sys
from pathlib import Path
with Path(sys.argv[1]).open(newline='') as f:
    rows=list(csv.DictReader(f))
if len(rows)!=1:
    raise SystemExit(f"[x21i] expected one n=3 mode row, found {len(rows)}")
r=rows[0]
omega=float(r['omegaFitEnsemble']); theory=float(r['omegaTheoryDeclared'])
lines=[
 '===== 0493x21i sigma=1000 n=3 THREE-SEED PILOT GATE =====',
 f"PILOT_GATE={r['status']}",
 'sigmaDeclared=1000',
 'mode=3',
 'seeds=4932501,4933501,4934501',
 f"omegaFit={omega:.12g}",
 f"omegaTheoryDeclared={theory:.12g}",
 f"omegaFitOverTheory={omega/theory:.12g}",
 f"fitR2={float(r['fitR2Ensemble']):.12g}",
 f"windowGainStd={float(r['windowGainStd']):.12g}",
 f"Gsigma={float(r['surfaceTensionGainEnsemble']):.12g}",
 f"sigmaEffRaw={float(r['sigmaEffectiveEnsemble']):.12g}",
 f"seedGainStd={float(r['seedGainStd']):.12g}",
 f"snrStartProxyEnsemble={float(r['snrStartProxyEnsemble']):.12g}",
 'policy=completion to n=2,4 is launched only when the unchanged x12cal n=3 ensemble status is PASS.',
]
Path(sys.argv[2]).write_text('\n'.join(lines)+'\n',encoding='utf-8')
print('\n'.join(lines))
PY

pilot_status="$(awk -F= '$1=="PILOT_GATE"{print $2}' "$PILOT_GATE")"
if [[ "$pilot_status" != PASS ]]; then
  echo
  echo "[x21i] n=3 sigma=1000 pilot is $pilot_status."
  echo "[x21i] Stopping here deliberately: n=2/n=4 are not launched."
  echo "[x21i] Diagnose signal/noise or linear-amplitude suitability before extending the campaign."
  echo "[x21i] decision file=$PILOT_GATE"
  exit 0
fi

# ---------------------------------------------------------------------------
# Stage 2: complete n=2 and n=4 only after a clean n=3 PASS.
# ---------------------------------------------------------------------------
for mode in 2 4; do
  for seed in $SEEDS; do
    run_case "$mode" "$seed"
  done
done

global_inputs=""
for mode in 2 3 4; do
  for seed in $SEEDS; do global_inputs="$global_inputs $(case_manifest "$mode" "$seed")"; done
done
# shellcheck disable=SC2086
combine_manifests "$GLOBAL_MANIFEST" "2,3,4" $global_inputs || die "cannot assemble global n=2,3,4 manifest"
analyze_manifest "$GLOBAL_MANIFEST" "$GLOBAL_ANALYSIS"

MODE_CSV="$GLOBAL_ANALYSIS/capillary_calibration_modes_0493x12cal.csv"
GLOBAL_CSV="$GLOBAL_ANALYSIS/capillary_calibration_0493x12cal.csv"
[[ -s "$MODE_CSV" ]] || die "global mode CSV missing: $MODE_CSV"
[[ -s "$GLOBAL_CSV" ]] || die "global calibration CSV missing: $GLOBAL_CSV"

python3 - "$MODE_CSV" "$GLOBAL_CSV" "$GLOBAL_GATE" <<'PY' || exit 2
import csv, sys
from pathlib import Path
mp,gp,out=map(Path,sys.argv[1:])
with mp.open(newline='') as f: modes=list(csv.DictReader(f))
with gp.open(newline='') as f: glob=list(csv.DictReader(f))
if len(modes)!=3 or len(glob)!=1:
    raise SystemExit(f"[x21i] unexpected analysis sizes modes={len(modes)} global={len(glob)}")
g=glob[0]; modes.sort(key=lambda r:int(float(r['mode'])))
lines=[
 '===== 0493x21i sigma=1000 ARTICLE CAPILLARY GLOBAL GATE =====',
 f"GLOBAL_GATE={g['status']}",
 'modes=2,3,4',
 'seeds=4932501,4933501,4934501',
 'sigmaDeclared=1000',
]
for r in modes:
    n=int(float(r['mode'])); om=float(r['omegaFitEnsemble']); th=float(r['omegaTheoryDeclared'])
    lines += [
      f"mode{n}Status={r['status']}",
      f"mode{n}OmegaFit={om:.12g}",
      f"mode{n}OmegaTheory={th:.12g}",
      f"mode{n}OmegaRatio={om/th:.12g}",
      f"mode{n}FitR2={float(r['fitR2Ensemble']):.12g}",
      f"mode{n}WindowGainStd={float(r['windowGainStd']):.12g}",
      f"mode{n}Gsigma={float(r['surfaceTensionGainEnsemble']):.12g}",
      f"mode{n}SigmaEffRaw={float(r['sigmaEffectiveEnsemble']):.12g}",
      f"mode{n}SeedGainStd={float(r['seedGainStd']):.12g}",
      f"mode{n}SnrStart={float(r['snrStartProxyEnsemble']):.12g}",
    ]
def v(name): return g.get(name,'')
lines += [
 f"GsigmaGlobalRaw={float(v('surfaceTensionGain')):.12g}",
 f"sigmaEffGlobalRaw={float(v('surfaceTensionEffectiveRaw')):.12g}",
 f"sigmaEffQualified={v('surfaceTensionEffective')}",
 f"modeGainMean={float(v('surfaceTensionGainModeMean')):.12g}",
 f"modeGainStd={float(v('surfaceTensionGainModeStd')):.12g}",
 f"crossModeRelativeStd={float(v('surfaceTensionGainModeRelativeStd')):.12g}",
 f"meanFitR2={float(v('meanFitR2')):.12g}",
 'qualification=unchanged x12cal rule: all three mode ensembles PASS, mean fit R2>=0.98, cross-mode relative gain std<=0.05.',
]
out.write_text('\n'.join(lines)+'\n',encoding='utf-8')
print('\n'.join(lines))
PY

# Optional non-gating comparison to the already-qualified sigma=10000 result.
if [[ -s "$BASELINE_GLOBAL" ]]; then
  python3 - "$BASELINE_GLOBAL" "$GLOBAL_CSV" "$CROSS_SIGMA" <<'PY' || true
import csv, math, sys
from pathlib import Path
p0,p1,out=map(Path,sys.argv[1:])
def one(p):
    with p.open(newline='') as f: rr=list(csv.DictReader(f))
    if len(rr)!=1: raise RuntimeError(f"expected one row in {p}")
    return rr[0]
a,b=one(p0),one(p1)
g0=float(a['surfaceTensionGain']); g1=float(b['surfaceTensionGain'])
s0=float(a['sigmaDeclared']); s1=float(b['sigmaDeclared'])
lines=[
 '===== 0493x21i CROSS-SIGMA COMPARISON (NON-GATING) =====',
 f"sigmaHigh={s0:.12g}", f"GsigmaHigh={g0:.12g}",
 f"sigmaLow={s1:.12g}", f"GsigmaLow={g1:.12g}",
 f"GsigmaLowOverHigh={g1/g0:.12g}",
 f"relativeGainChange={(g1-g0)/g0:.12g}",
 f"declaredSigmaRatio={s1/s0:.12g}",
 f"idealOmegaRatio=sqrt(sigmaLow/sigmaHigh)={math.sqrt(s1/s0):.12g}",
 'note=this comparison is descriptive only and is not used by the x12cal qualification gate.',
]
out.write_text('\n'.join(lines)+'\n',encoding='utf-8')
print('\n'.join(lines))
PY
else
  echo "[x21i] baseline sigma=10000 global CSV not found; cross-sigma comparison skipped: $BASELINE_GLOBAL"
fi

echo
echo "[x21i] COMPLETE"
echo "[x21i] pilot gate=$PILOT_GATE"
echo "[x21i] global gate=$GLOBAL_GATE"
echo "[x21i] modes=$MODE_CSV"
echo "[x21i] global calibration=$GLOBAL_CSV"
echo "[x21i] cross-sigma comparison=$CROSS_SIGMA"
