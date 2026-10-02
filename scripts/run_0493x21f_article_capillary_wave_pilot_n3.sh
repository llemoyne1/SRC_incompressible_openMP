#!/usr/bin/env bash
set -euo pipefail

ROOT="${ROOT:-/mnt/e/SRC_MPCD_DEV/SRC_GPU-SURF}"
cd "$ROOT"

BASE_RUNNER="$ROOT/scripts/run_0493x12cal_capillary_calibrator.sh"
ANALYZER="$ROOT/scripts/analyze_0493x12cal_capillary_calibrator.py"
GENERATOR="$ROOT/scripts/generate_0493x11b_capillary_wave_state.py"
BIN="$ROOT/build/src_mpcd_base_cuda_q6_resident_livevis_0486"
EXPECTED_BIN_SHA256="422a199e0bdd2ae0525f41a332299cabec268fee7d04957d839e1e765a806ecc"

for f in "$BASE_RUNNER" "$ANALYZER" "$GENERATOR" "$BIN"; do
  [[ -f "$f" ]] || { echo "[x21f-pilot] ERROR missing required file: $f" >&2; exit 2; }
done
[[ -x "$BIN" ]] || { echo "[x21f-pilot] ERROR binary is not executable: $BIN" >&2; exit 2; }

actual_sha="$(sha256sum "$BIN" | awk '{print $1}')"
if [[ "$actual_sha" != "$EXPECTED_BIN_SHA256" ]]; then
  echo "[x21f-pilot] ERROR binary SHA mismatch" >&2
  echo "[x21f-pilot] expected=$EXPECTED_BIN_SHA256" >&2
  echo "[x21f-pilot] actual  =$actual_sha" >&2
  echo "[x21f-pilot] No rebuild is allowed for this article campaign." >&2
  exit 2
fi

# Build a temporary orchestration-only derivative of x12cal.
# The historical file in scripts/ is left untouched.
tmp_runner="$(mktemp /tmp/run_0493x21f_x12cal_XXXXXX.sh)"
trap 'rm -f "$tmp_runner"' EXIT
python3 - "$BASE_RUNNER" "$tmp_runner" <<'PY'
from pathlib import Path
import sys
src = Path(sys.argv[1]).read_text(encoding="utf-8")

old = "PROJECTION_MOMENTUM_CORRECTION_ENABLE=true"
if src.count(old) != 1:
    raise SystemExit(f"[x21f-pilot] expected exactly one '{old}', found {src.count(old)}")
src = src.replace(old, "PROJECTION_MOMENTUM_CORRECTION_ENABLE=false", 1)

needle = "Q6_STRICT=1"
if needle not in src:
    raise SystemExit("[x21f-pilot] Q6_STRICT=1 anchor not found in x12cal runner")
if "Q6_FORCE_PROJECTION_MODE=prestream_single_fused" not in src:
    src = src.replace(
        needle,
        needle + "\nQ6_FORCE_PROJECTION_MODE=prestream_single_fused",
        1,
    )

Path(sys.argv[2]).write_text(src, encoding="utf-8")
PY
chmod 700 "$tmp_runner"

# Exact nominal article fluid / current qualified particle-field closure.
export BIN
export LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
export PROFILE=production
export MODES="3"
export REPLICATES=1
export RUN_PERIODS=2.0
export SAMPLES_PER_PERIOD=80
export FIT_PERIODS=1.0
export SENSITIVITY_PERIODS=0.75,1.0,1.25

export NX=256
export NY=128
export Lx=1.0
export Ly=0.5
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

# Explicitly retain the qualified full-vector x13h kinetic closure and keep
# later experimental branches disabled.
export MPCD_X10_KINETIC_INTERFACE_ONE_FOR_ONE_NORMAL_ONLY=0
export MPCD_X10_KINETIC_INTERFACE_FREE_CROSSING_CELLS=0.0
export MPCD_X13R_INTERFACE_CELL_COOLING=0
export MPCD_X13S_INTERFACE_ANISOTROPIC_COOLING=0
export MPCD_X13T_UNIFIED_PROGRESSIVE_INTERFACE_COOLING=0
export MPCD_X13W_ESCAPE_RESEED=0

export BASE_SEED=4932501
export SEED_STRIDE=1009
export KINEMATIC_VISCOSITY=0.00051019788
export CHARACTERISTIC_U=-1
export CHARACTERISTIC_D=-1
export GRAVITY_MAGNITUDE=0

export LIVE_VIS_ENABLE=0
export CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}"
export RUN_ROOT="${RUN_ROOT:-runs/0493x21f_article_capillary_wave_pilot_n3_seed4932501}"
export PREFLIGHT_ONLY="${PREFLIGHT_ONLY:-0}"
export ANALYZE_ONLY="${ANALYZE_ONLY:-0}"

cat <<HDR
===== 0493x21f ARTICLE CAPILLARY-WAVE PILOT =====
mode=3 seed=4932501
fluid: h=1/256 dt=$DT kBT=$KBT m=1 gamma=$GAMMA alphaSRC=120deg rho=524288
geometry: 256x128 Lx=1 Ly=0.5 H=0.25 amplitude=2h
sigmaDeclared=$SIGMA_DECLARED minRadiusCells=$SURFACE_TENSION_MIN_RADIUS_CELLS
projectionMomentumCorrection=false q6ForceProjectionMode=prestream_single_fused
kineticClosure=qualified-x13h full-vector one-for-one swap, x12a=ON
binary=$BIN
binarySHA256=$actual_sha
runRoot=$RUN_ROOT
note=global x12cal status is expected to be INVALID for a one-mode pilot; use PILOT_GATE below.
HDR

ROOT="$ROOT" bash "$tmp_runner"

if [[ "$PREFLIGHT_ONLY" == 1 ]]; then
  echo "[x21f-pilot] PREFLIGHT_ONLY complete; no simulation launched."
  exit 0
fi

MODE_CSV="$RUN_ROOT/analysis/capillary_calibration_modes_0493x12cal.csv"
[[ -s "$MODE_CSV" ]] || { echo "[x21f-pilot] ERROR missing mode analysis: $MODE_CSV" >&2; exit 2; }

python3 - "$MODE_CSV" "$RUN_ROOT/analysis/pilot_gate_0493x21f.txt" <<'PY'
import csv, math, sys
from pathlib import Path
p = Path(sys.argv[1])
with p.open(newline="") as f:
    rows = list(csv.DictReader(f))
if len(rows) != 1:
    raise SystemExit(f"[x21f-pilot] expected one mode row, found {len(rows)}")
r = rows[0]
mode = int(float(r["mode"]))
status = r["status"]
r2 = float(r["fitR2Ensemble"])
omega = float(r["omegaFitEnsemble"])
omega_th = float(r["omegaTheoryDeclared"])
gain = float(r["surfaceTensionGainEnsemble"])
sigma_eff = float(r["sigmaEffectiveEnsemble"])
window_std = float(r["windowGainStd"])
frames = int(float(r["fitFramesEnsemble"]))

if mode != 3 or not all(map(math.isfinite, [r2, omega, omega_th, gain, sigma_eff, window_std])):
    gate = "INVALID"
elif status == "PASS" and r2 >= 0.98:
    gate = "PASS"
elif status in ("PASS", "REVIEW") and r2 >= 0.90:
    gate = "REVIEW"
else:
    gate = "INVALID"

lines = [
    "===== 0493x21f CAPILLARY-WAVE PILOT GATE =====",
    f"PILOT_GATE={gate}",
    f"mode={mode}",
    f"calibratorModeStatus={status}",
    f"omegaFit={omega:.12g}",
    f"omegaTheoryDeclared={omega_th:.12g}",
    f"omegaFitOverTheory={omega/omega_th:.12g}",
    f"fitR2={r2:.12g}",
    f"windowGainStd={window_std:.12g}",
    f"fitFrames={frames}",
    f"G_sigma_raw_mode={gain:.12g}",
    f"sigmaEffRaw_mode={sigma_eff:.12g}",
    "note=single-mode pilot does not qualify the global sigma_eff; cross-mode calibration requires n=2,3,4.",
]
Path(sys.argv[2]).write_text("\n".join(lines) + "\n", encoding="utf-8")
print("\n".join(lines))
PY

echo "[x21f-pilot] gate=$RUN_ROOT/analysis/pilot_gate_0493x21f.txt"
