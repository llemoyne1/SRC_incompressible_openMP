#!/usr/bin/env bash
set -euo pipefail

# 0493x13j — Young–Laplace qualification of the x13h reference fluid
#
# Qualification/tooling only:
#   - no C++/CUDA modification
#   - reuses the current x12yl Young–Laplace calibrator and its x9e/x9r/x12a audits
#   - x13h microscopic fluid is fixed explicitly
#
# Recommended sequence:
#   MODE=preflight  bash scripts/run_0493x13j_young_laplace_x13h_s120.sh
#   MODE=smoke      bash scripts/run_0493x13j_young_laplace_x13h_s120.sh
#   # inspect/return the smoke outputs before:
#   MODE=production bash scripts/run_0493x13j_young_laplace_x13h_s120.sh
#
# The smoke is one strict sigma=0 / sigma=120 pair at R/h=40.
# A one-pair x12yl global regression cannot have a meaningful multi-point R²:
# the pair CSV is the primary smoke result.  The production campaign is the
# actual 3 radii x 3 seeds x 2 sigma states qualification.

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

X12YL="scripts/run_0493x12yl_young_laplace_calibrator.sh"
ANALYZER="scripts/analyze_0493x12yl_young_laplace_calibrator.py"
PARENT="scripts/run_0493x10o_q6_thermal_interface_static_drop.sh"

for f in "$X12YL" "$ANALYZER" "$PARENT"; do
  [[ -f "$f" ]] || {
    echo "[0493x13j] ERROR missing required existing file: $f" >&2
    exit 2
  }
done

MODE="${MODE:-preflight}"

# -----------------------------------------------------------------------------
# x13h reference fluid — fixed local signature
# -----------------------------------------------------------------------------
export NX="${NX:-256}"
export NY="${NY:-256}"
export Lx="${Lx:-1.0}"
export Ly="${Ly:-1.0}"

export GAMMA="${GAMMA:-8}"
export KBT="${KBT:-0.125}"
export LIQUID_MASS="${LIQUID_MASS:-1.0}"

# lambda/h = 0.72 at h=1/256, kBT=0.125, m=1:
# dt = (lambda/h) h / sqrt(pi*kBT/(2m))
X13H_DT="0.0063471328149122585"
export DT="${DT:-$X13H_DT}"

export ROTATION_ANGLE="${ROTATION_ANGLE:-2.0943951023931953}"   # 120 deg
export RANDOM_ROTATION_SIGN="${RANDOM_ROTATION_SIGN:-true}"
export GRID_SHIFT_ENABLE="${GRID_SHIFT_ENABLE:-true}"

export THERMOSTAT_ENABLE="${THERMOSTAT_ENABLE:-true}"
export THERMOSTAT_MODE="${THERMOSTAT_MODE:-cell_relative_rescale}"
export THERMOSTAT_EVERY="${THERMOSTAT_EVERY:-1}"
export THERMOSTAT_TARGET_KBT="${THERMOSTAT_TARGET_KBT:-$KBT}"
export THERMOSTAT_MIN_PARTICLES="${THERMOSTAT_MIN_PARTICLES:-3}"

# -----------------------------------------------------------------------------
# Mechanical surface-tension qualification
# -----------------------------------------------------------------------------
export SIGMA_DECLARED="${SIGMA_DECLARED:-1200}"
export SURFACE_TENSION_MIN_RADIUS_CELLS="${SURFACE_TENSION_MIN_RADIUS_CELLS:-4}"

# Keep the production x12a chain active, but require it to be inactive on the
# resolved calibration drops (this is the current x12yl contract).
export MPCD_X12A_LOCAL_THERMAL_RADIUS_CELLS="${MPCD_X12A_LOCAL_THERMAL_RADIUS_CELLS:-25.298221281347036}"
export ALLOW_LOCAL_COOLING="${ALLOW_LOCAL_COOLING:-0}"

export BASE_SEED="${BASE_SEED:-4931301}"
export SEED_STRIDE="${SEED_STRIDE:-1009}"
export TAIL_START="${TAIL_START:-0.50}"

# Preserve the historical physical qualification horizon (~2 time units) while
# exploiting the larger x13h dt.  316 * dt = 2.0056939695.
export STEPS="${STEPS:-316}"

# Historical x12yl sampled every 10 steps at dt=.002 => Delta t_sample=.02.
# 3 x x13h dt = .0190414, so SUMMARY_EVERY=3 preserves nearly the same
# physical diagnostic cadence.
export SUMMARY_EVERY="${SUMMARY_EVERY:-3}"

# No heavy field recording is needed for static Young–Laplace.  Existing x9e,
# x9r and x12a CSV audits remain generated at the summary cadence.
export DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-0}"
export LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
export LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
export LIVE_VIS_HOLD_ON_EXIT="${LIVE_VIS_HOLD_ON_EXIT:-1}"
export LIVE_VIS_RECORD_ENABLE="${LIVE_VIS_RECORD_ENABLE:-0}"
export FILTERED_RECORDING_ENABLE="${FILTERED_RECORDING_ENABLE:-0}"
export THREADS="${THREADS:-8}"

SMOKE_RUN_ROOT="${SMOKE_RUN_ROOT:-runs/0493x13j_young_laplace_x13h_s120_smoke}"
PROD_RUN_ROOT="${PROD_RUN_ROOT:-runs/0493x13j_young_laplace_x13h_s120}"

# -----------------------------------------------------------------------------
# Preflight: verify that the requested numbers really describe the x13h point.
# This is a runner-side consistency check only; it changes no simulation physics.
# -----------------------------------------------------------------------------
python3 - "$Lx" "$Ly" "$NX" "$NY" "$GAMMA" "$KBT" "$LIQUID_MASS" "$DT" \
          "$ROTATION_ANGLE" "$SIGMA_DECLARED" "$SURFACE_TENSION_MIN_RADIUS_CELLS" <<'PY'
import math, sys
lx,ly=float(sys.argv[1]),float(sys.argv[2])
nx,ny=int(sys.argv[3]),int(sys.argv[4])
gamma=float(sys.argv[5]); kbt=float(sys.argv[6]); mass=float(sys.argv[7])
dt=float(sys.argv[8]); alpha=float(sys.argv[9])
sigma=float(sys.argv[10]); rmin=float(sys.argv[11])

hx,hy=lx/nx,ly/ny
if abs(hx-hy) > 1e-12*max(1.0,abs(hx),abs(hy)):
    raise SystemExit("[0493x13j] ERROR square cells required")
target_dt=0.72*hx/math.sqrt(math.pi*kbt/(2.0*mass))
rel=abs(dt-target_dt)/target_dt
if rel > 1e-10:
    raise SystemExit(
        f"[0493x13j] ERROR DT={dt:.17g} is not x13h lambda/h=0.72 "
        f"(expected {target_dt:.17g}, rel={rel:.3e})"
    )
if abs(gamma-8.0) > 1e-12:
    raise SystemExit(f"[0493x13j] ERROR x13h qualification requires gamma=8, got {gamma}")
if abs(alpha-2.0943951023931953) > 1e-12:
    raise SystemExit(f"[0493x13j] ERROR x13h qualification requires alpha=120deg, got {alpha}")
if rmin != 4.0:
    raise SystemExit(f"[0493x13j] ERROR this qualification locks minRadiusCells=4, got {rmin}")
if sigma <= 0.0:
    raise SystemExit(f"[0493x13j] ERROR SIGMA_DECLARED must be positive, got {sigma}")

rho=gamma*mass/(hx*hy)
R40=40.0*hx
dp=sigma/R40
pth=gamma*kbt/(hx*hy)
print("===== 0493x13j X13H / YOUNG-LAPLACE CONTRACT =====")
print(f"grid={nx}x{ny} L=({lx:.9g},{ly:.9g}) h={hx:.12g}")
print(f"fluid gamma={gamma:.9g} kBT={kbt:.9g} mass={mass:.9g}")
print(f"collision alpha={alpha:.16g} rad = {math.degrees(alpha):.9g} deg")
print(f"lambda/h=0.72 dt={dt:.16g} targetDt={target_dt:.16g}")
print(f"rhoRef={rho:.12g}")
print(f"sigmaDeclared={sigma:.12g} minRadiusCells={rmin:.9g}")
print(f"R40={R40:.12g} dpTheory_R40={dp:.12g} pThermalProxy={pth:.12g} dp/pThermal={dp/pth:.6%}")
print(f"steps={int(float(__import__('os').environ.get('STEPS','316')))} "
      f"physicalTime={int(float(__import__('os').environ.get('STEPS','316')))*dt:.12g} "
      f"summaryEvery={__import__('os').environ.get('SUMMARY_EVERY','3')}")
PY

print_pair_summary() {
  local run_root="$1"
  local pair_csv="$run_root/analysis/young_laplace_pairs_0493x12yl.csv"
  if [[ ! -s "$pair_csv" ]]; then
    echo "[0493x13j] WARNING pair CSV not found at $pair_csv"
    return 0
  fi

  python3 - "$pair_csv" <<'PY'
import csv, math, sys
p=sys.argv[1]
with open(p,newline="") as f:
    rows=list(csv.DictReader(f))
print("===== 0493x13j SMOKE PAIR SUMMARY =====")
if not rows:
    print("pairRows=0")
    raise SystemExit(0)

for r in rows:
    def get(*names):
        for n in names:
            if n in r and r[n] not in ("",None):
                return r[n]
        return "NA"
    print(
        "R/h=" + get("r_cells","radiusCells","R_over_h") +
        " seed=" + get("seed") +
        " dpCap=" + get("pressure_capillary_increment","deltaPressureCapillary","dpCap","deltaP") +
        " kappaActive=" + get("kappa_active","activeMeanKappa","meanKappaActive","kappaActive") +
        " gain=" + get("gainVsKappa","gain_vs_kappa","gain") +
        " sigmaEffPair=" + get("sigmaEffectivePair","sigma_effective_pair","sigmaEffective") +
        " clipTailMax=" + get("maxTailClipFraction","max_tail_clip_fraction","clipFraction")
    )
print("NOTE: one paired point is a smoke test, not a multi-radius x12yl qualification.")
print("      A global R^2/status from this smoke can therefore be REVIEW/INVALID by construction.")
PY
}

run_preflight() {
  echo
  echo "===== 0493x13j STAGE: PREFLIGHT (R/h=40, one pair geometry) ====="
  PROFILE=quick \
  RADII="40" \
  REPLICATES=1 \
  RUN_ROOT="$SMOKE_RUN_ROOT" \
  PREFLIGHT_ONLY=1 \
  ANALYZE_ONLY=0 \
  CLEAN_RUN_ROOT=0 \
  bash "$X12YL"
}

run_smoke() {
  echo
  echo "===== 0493x13j STAGE: SMOKE (R/h=40, sigma=0/120, one seed) ====="
  PROFILE=quick \
  RADII="40" \
  REPLICATES=1 \
  RUN_ROOT="$SMOKE_RUN_ROOT" \
  PREFLIGHT_ONLY=0 \
  ANALYZE_ONLY=0 \
  CLEAN_RUN_ROOT=1 \
  bash "$X12YL"

  print_pair_summary "$SMOKE_RUN_ROOT"

  echo
  echo "[0493x13j] smokeRoot=$SMOKE_RUN_ROOT"
  echo "[0493x13j] Return/archive before production:"
  echo "  $SMOKE_RUN_ROOT/analysis/"
  echo "  $SMOKE_RUN_ROOT/manifest_0493x12yl.csv"
  echo "  $SMOKE_RUN_ROOT/*/output/cuda_static_drop_pressure_0493x9e.csv"
  echo "  $SMOKE_RUN_ROOT/*/output/cuda_surface_tension_limiter_0493x9r.csv"
  echo "  $SMOKE_RUN_ROOT/*/output/cuda_x12a_local_thermal_cooling.csv (if present)"
  echo "[0493x13j] Do not launch production until the smoke has been reviewed."
}

run_production() {
  echo
  echo "===== 0493x13j STAGE: PRODUCTION ====="
  echo "[0493x13j] matrix: R/h={32,40,48} x 3 seeds x {sigma=0,sigma=120} = 18 runs"
  PROFILE=production \
  RADII="32 40 48" \
  REPLICATES=3 \
  RUN_ROOT="$PROD_RUN_ROOT" \
  PREFLIGHT_ONLY=0 \
  ANALYZE_ONLY=0 \
  CLEAN_RUN_ROOT=1 \
  bash "$X12YL"

  echo
  echo "[0493x13j] productionRoot=$PROD_RUN_ROOT"
  echo "[0493x13j] primaryReport=$PROD_RUN_ROOT/analysis/young_laplace_calibration_report_0493x12yl.txt"
}

run_analyze() {
  echo
  echo "===== 0493x13j STAGE: ANALYZE-ONLY PRODUCTION ROOT ====="
  PROFILE=production \
  RADII="32 40 48" \
  REPLICATES=3 \
  RUN_ROOT="$PROD_RUN_ROOT" \
  PREFLIGHT_ONLY=0 \
  ANALYZE_ONLY=1 \
  CLEAN_RUN_ROOT=0 \
  bash "$X12YL"
}

case "$MODE" in
  preflight)  run_preflight ;;
  smoke)      run_smoke ;;
  production) run_production ;;
  analyze)    run_analyze ;;
  *)
    echo "[0493x13j] ERROR MODE must be one of: preflight smoke production analyze" >&2
    exit 2
    ;;
esac
