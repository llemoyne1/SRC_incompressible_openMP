#!/usr/bin/env bash
# 0493x21f — second n=3 realization + two-seed ensemble analysis.
# Article orchestration only. No C++/CUDA modification, no recompilation.

ROOT="${ROOT:-/mnt/e/SRC_MPCD_DEV/SRC_GPU-SURF}"
cd "$ROOT" || { echo "[x21f-n3e2] ERROR cannot cd to $ROOT" >&2; exit 2; }

BASE_RUNNER="$ROOT/scripts/run_0493x12cal_capillary_calibrator.sh"
ANALYZER="$ROOT/scripts/analyze_0493x12cal_capillary_calibrator.py"
GENERATOR="$ROOT/scripts/generate_0493x11b_capillary_wave_state.py"
BIN="$ROOT/build/src_mpcd_base_cuda_q6_resident_livevis_0486"
EXPECTED_BIN_SHA256="422a199e0bdd2ae0525f41a332299cabec268fee7d04957d839e1e765a806ecc"

SEED1_ROOT="${SEED1_ROOT:-runs/0493x21f_article_capillary_wave_pilot_n3_seed4932501}"
SEED2_ROOT="${SEED2_ROOT:-runs/0493x21f_article_capillary_wave_pilot_n3_seed4933501}"
ENSEMBLE_ROOT="${ENSEMBLE_ROOT:-runs/0493x21f_article_capillary_wave_n3_ensemble_seed4932501_4933501}"

SEED1_MANIFEST="$SEED1_ROOT/manifest_0493x12cal.csv"
SEED2_MANIFEST="$SEED2_ROOT/manifest_0493x12cal.csv"
ENSEMBLE_MANIFEST="$ENSEMBLE_ROOT/manifest_0493x12cal.csv"

die() { echo "[x21f-n3e2] ERROR $*" >&2; exit 2; }

for f in "$BASE_RUNNER" "$ANALYZER" "$GENERATOR" "$BIN"; do
  [[ -f "$f" ]] || die "missing required file: $f"
done
[[ -x "$BIN" ]] || die "binary is not executable: $BIN"
[[ -s "$SEED1_MANIFEST" ]] || die "first-seed manifest missing: $SEED1_MANIFEST"

actual_sha="$(sha256sum "$BIN" | awk '{print $1}')"
[[ "$actual_sha" == "$EXPECTED_BIN_SHA256" ]] || die "binary SHA mismatch: expected=$EXPECTED_BIN_SHA256 actual=$actual_sha; no rebuild allowed"

# Verify that the existing pilot is exactly the expected n=3 / seed 4932501 realization.
python3 - "$SEED1_MANIFEST" <<'PY' || exit 2
import csv, sys
from pathlib import Path
p=Path(sys.argv[1])
with p.open(newline='') as f:
    rows=list(csv.DictReader(f))
if len(rows)!=1:
    raise SystemExit(f"[x21f-n3e2] expected one seed-1 manifest row, found {len(rows)}")
r=rows[0]
checks = {
    'mode': '3', 'seed': '4932501', 'sigma_declared': '10000',
    'gamma': '8', 'kBT': '0.125', 'min_radius_cells': '4',
    'calibration_path': 'src-q6-g-f'
}
for k,v in checks.items():
    got=r.get(k,'')
    if float(got)==float(v) if k not in ('calibration_path',) else got==v:
        continue
    raise SystemExit(f"[x21f-n3e2] seed-1 manifest mismatch {k}: got={got} expected={v}")
print('[x21f-n3e2] seed-1 manifest identity PASS')
PY

# Temporary orchestration derivative of x12cal: leave historical runner untouched.
tmp_runner="$(mktemp /tmp/run_0493x21f_x12cal_XXXXXX.sh)" || die "mktemp failed"
cleanup() { rm -f "$tmp_runner"; }
trap cleanup EXIT
python3 - "$BASE_RUNNER" "$tmp_runner" <<'PY' || exit 2
from pathlib import Path
import sys
src=Path(sys.argv[1]).read_text(encoding='utf-8')
old='PROJECTION_MOMENTUM_CORRECTION_ENABLE=true'
if src.count(old)!=1:
    raise SystemExit(f"[x21f-n3e2] expected exactly one '{old}', found {src.count(old)}")
src=src.replace(old,'PROJECTION_MOMENTUM_CORRECTION_ENABLE=false',1)
needle='Q6_STRICT=1'
if needle not in src:
    raise SystemExit('[x21f-n3e2] Q6_STRICT=1 anchor not found')
if 'Q6_FORCE_PROJECTION_MODE=prestream_single_fused' not in src:
    src=src.replace(needle,needle+'\nQ6_FORCE_PROJECTION_MODE=prestream_single_fused',1)
Path(sys.argv[2]).write_text(src,encoding='utf-8')
PY
chmod 700 "$tmp_runner" || die "cannot chmod temporary runner"

# Exact nominal article fluid and qualified free-surface chain.
export BIN
export LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
export PROFILE=production
export MODES="3"
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

export BASE_SEED=4933501
export SEED_STRIDE=1000
export KINEMATIC_VISCOSITY=0.00051019788
export CHARACTERISTIC_U=-1
export CHARACTERISTIC_D=-1
export GRAVITY_MAGNITUDE=0
export LIVE_VIS_ENABLE=0
export CLEAN_RUN_ROOT=1
export RUN_ROOT="$SEED2_ROOT"
export PREFLIGHT_ONLY=0
export ANALYZE_ONLY=0

cat <<HDR
===== 0493x21f n=3 SECOND SEED =====
mode=3 seed=4933501
binarySHA256=$actual_sha
runRoot=$SEED2_ROOT
postprocess=combine existing seed4932501 + new seed4933501 and refit ensemble before frequency extraction
HDR

ROOT="$ROOT" bash "$tmp_runner" || die "seed 4933501 run/analyze failed"
[[ -s "$SEED2_MANIFEST" ]] || die "second-seed manifest missing after run: $SEED2_MANIFEST"

mkdir -p "$ENSEMBLE_ROOT/analysis" || die "cannot create ensemble root"
python3 - "$SEED1_MANIFEST" "$SEED2_MANIFEST" "$ENSEMBLE_MANIFEST" <<'PY' || exit 2
import csv, sys
from pathlib import Path
p1,p2,out=map(Path,sys.argv[1:])
def read_one(p):
    with p.open(newline='') as f:
        rows=list(csv.DictReader(f))
    if len(rows)!=1:
        raise SystemExit(f"[x21f-n3e2] expected one row in {p}, got {len(rows)}")
    return rows[0]
r1,r2=read_one(p1),read_one(p2)
if r1.keys()!=r2.keys():
    raise SystemExit('[x21f-n3e2] manifest schemas differ')
for r,seed in ((r1,4932501),(r2,4933501)):
    if int(float(r['mode']))!=3 or int(float(r['seed']))!=seed:
        raise SystemExit(f"[x21f-n3e2] unexpected mode/seed row: mode={r['mode']} seed={r['seed']}")
for k in ('sigma_declared','Lx','Ly','nx','ny','h','gamma','liquid_mass','kBT','mean_height','amplitude_cells','min_radius_cells','calibration_path','x12a_radius_cells'):
    if r1[k] != r2[k]:
        try:
            same=abs(float(r1[k])-float(r2[k])) <= 1e-12*max(1.0,abs(float(r1[k])),abs(float(r2[k])))
        except Exception:
            same=False
        if not same:
            raise SystemExit(f"[x21f-n3e2] incompatible manifests at {k}: {r1[k]} vs {r2[k]}")
out.parent.mkdir(parents=True,exist_ok=True)
with out.open('w',newline='') as f:
    w=csv.DictWriter(f,fieldnames=list(r1.keys()))
    w.writeheader(); w.writerow(r1); w.writerow(r2)
print(f"[x21f-n3e2] combined manifest={out}")
PY

python3 "$ANALYZER" \
  --manifest "$ENSEMBLE_MANIFEST" \
  --output-dir "$ENSEMBLE_ROOT/analysis" \
  --fit-periods 1.0 \
  --sensitivity-periods 0.75,1.0,1.25 \
  --characteristic-U -1 \
  --characteristic-D -1 \
  --kinematic-viscosity 0.00051019788 \
  --gravity 0 || die "two-seed ensemble analysis failed"

MODE_CSV="$ENSEMBLE_ROOT/analysis/capillary_calibration_modes_0493x12cal.csv"
GATE="$ENSEMBLE_ROOT/analysis/ensemble_gate_0493x21f_n3_2seeds.txt"
[[ -s "$MODE_CSV" ]] || die "ensemble mode CSV missing"

python3 - "$MODE_CSV" "$GATE" <<'PY' || exit 2
import csv, math, sys
from pathlib import Path
with Path(sys.argv[1]).open(newline='') as f:
    rows=list(csv.DictReader(f))
if len(rows)!=1:
    raise SystemExit(f"[x21f-n3e2] expected one ensemble mode row, found {len(rows)}")
r=rows[0]
status=r['status']
vals={
 'omegaFit':float(r['omegaFitEnsemble']),
 'omegaTheory':float(r['omegaTheoryDeclared']),
 'fitR2':float(r['fitR2Ensemble']),
 'windowGainStd':float(r['windowGainStd']),
 'gain':float(r['surfaceTensionGainEnsemble']),
 'sigma':float(r['sigmaEffectiveEnsemble']),
 'seedGainMean':float(r['seedGainMean']),
 'seedGainStd':float(r['seedGainStd']),
 'snr':float(r['snrStartProxyEnsemble']),
}
lines=[
 '===== 0493x21f n=3 TWO-SEED ENSEMBLE GATE =====',
 f'ENSEMBLE_GATE={status}',
 'mode=3',
 'seeds=4932501,4933501',
 f"omegaFit={vals['omegaFit']:.12g}",
 f"omegaTheoryDeclared={vals['omegaTheory']:.12g}",
 f"omegaFitOverTheory={vals['omegaFit']/vals['omegaTheory']:.12g}",
 f"fitR2={vals['fitR2']:.12g}",
 f"windowGainStd={vals['windowGainStd']:.12g}",
 f"G_sigma_raw_mode={vals['gain']:.12g}",
 f"sigmaEffRaw_mode={vals['sigma']:.12g}",
 f"seedGainMean={vals['seedGainMean']:.12g}",
 f"seedGainStd={vals['seedGainStd']:.12g}",
 f"snrStartProxyEnsemble={vals['snr']:.12g}",
 'note=global sigma_eff is still NOT qualified: final calibration requires modes n=2,3,4.',
]
Path(sys.argv[2]).write_text('\n'.join(lines)+'\n',encoding='utf-8')
print('\n'.join(lines))
PY

echo "[x21f-n3e2] COMPLETE"
echo "[x21f-n3e2] next decision file=$GATE"
