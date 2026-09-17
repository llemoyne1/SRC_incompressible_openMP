#!/usr/bin/env bash
# 0493x19b-fix4 — high-SNR prescribed annular Couette torque qualification.
# Physics is unchanged.  Start from an established Omega=0.05 bounceback state,
# add the exact Couette mean-flow increment to Omega=0.20, then run one
# bounceback realization with every-step wall torque diagnostics.

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT" || exit 2

TARGET_OMEGA_Z="${TARGET_OMEGA_Z:-0.20}"
SOURCE_OMEGA_Z_DEFAULT="${SOURCE_OMEGA_Z_DEFAULT:-0.05}"
RUN_STEPS="${RUN_STEPS:-5000}"
ANALYSIS_START_STEP="${ANALYSIS_START_STEP:-500}"
BASE_RUN_ROOT="${BASE_RUN_ROOT:-runs/0493x19b_fix4_highsnr_omega020/bounceback}"
SEED="${SEED:-4931940}"
CENTER_X="${CENTER_X:-0.5}"
CENTER_Y="${CENTER_Y:-0.5}"
INNER_RADIUS="${INNER_RADIUS:-0.20}"
OUTER_RADIUS="${OUTER_RADIUS:-0.35}"

SOURCE_OUTPUT="${SOURCE_OUTPUT:-runs/0493x19b_fix3_full_angular_audit/bounceback/fresh/output}"
SOURCE_RUN_ROOT="${SOURCE_RUN_ROOT:-runs/0493x19b_fix3_full_angular_audit/bounceback/fresh}"
if [[ ! -d "$SOURCE_OUTPUT" ]]; then
  SOURCE_OUTPUT="runs/0493x19b_fix2_angular_balance/bounceback/fresh/output"
  SOURCE_RUN_ROOT="runs/0493x19b_fix2_angular_balance/bounceback/fresh"
fi
if [[ ! -d "$SOURCE_OUTPUT" ]]; then
  SOURCE_OUTPUT="runs/0493x19b_fix1_torque_split/bounceback/fresh/output"
  SOURCE_RUN_ROOT="runs/0493x19b_fix1_torque_split/bounceback/fresh"
fi
if [[ ! -d "$SOURCE_OUTPUT" ]]; then
  SOURCE_OUTPUT="runs/0493x19b_prescribed_rotating_annulus_pair/bounceback/fresh/output"
  SOURCE_RUN_ROOT="runs/0493x19b_prescribed_rotating_annulus_pair/bounceback/fresh"
fi
if [[ ! -d "$SOURCE_OUTPUT" ]]; then
  echo "[0493x19b-fix4] ERROR: no established x19b bounceback output found" >&2
  exit 2
fi

LATEST_STATE="$(find "$SOURCE_OUTPUT" -maxdepth 1 -type f -name 'state_step_*.smpcd' -print | sort -V | tail -n 1)"
if [[ -z "$LATEST_STATE" || ! -s "$LATEST_STATE" ]]; then
  echo "[0493x19b-fix4] ERROR: no restart state in $SOURCE_OUTPUT" >&2
  exit 2
fi
SOURCE_STEP="$(basename "$LATEST_STATE" | sed -n 's/^state_step_0*\([0-9][0-9]*\)\.smpcd$/\1/p')"
[[ -n "$SOURCE_STEP" ]] || SOURCE_STEP=0

SOURCE_OMEGA_Z="$SOURCE_OMEGA_Z_DEFAULT"
META="$ROOT/$SOURCE_RUN_ROOT/run_meta_0493x19b.txt"
if [[ -s "$META" ]]; then
  parsed="$(sed -n 's/^omegaZ=//p' "$META" | tail -n 1)"
  [[ -n "$parsed" ]] && SOURCE_OMEGA_Z="$parsed"
fi

python3 - "$SOURCE_OMEGA_Z" "$TARGET_OMEGA_Z" <<'PY'
import math,sys
s=float(sys.argv[1]); t=float(sys.argv[2])
if not (math.isfinite(s) and math.isfinite(t) and t!=s):
    raise SystemExit('[0493x19b-fix4] source/target omega invalid or identical')
if abs(s-0.05)>1e-10:
    raise SystemExit(f'[0493x19b-fix4] expected an established Omega=0.05 source, got {s:.17g}; override only after review')
if abs(t-0.20)>1e-10:
    raise SystemExit(f'[0493x19b-fix4] qualification target is Omega=0.20, got {t:.17g}')
PY

INIT_DIR="$ROOT/runs/0493x19b_fix4_highsnr_omega020/restart_init"
mkdir -p "$INIT_DIR"
BOOSTED_STATE="$INIT_DIR/state_boosted_from_omega005_to_omega020.smpcd"
python3 "$ROOT/tools/prepare_0493x19b_fix4_couette_boost_restart.py" \
  --input "$LATEST_STATE" \
  --output "$BOOSTED_STATE" \
  --center-x "$CENTER_X" --center-y "$CENTER_Y" \
  --inner-radius "$INNER_RADIUS" --outer-radius "$OUTER_RADIUS" \
  --source-omega "$SOURCE_OMEGA_Z" --target-omega "$TARGET_OMEGA_Z" || exit 2

printf '\n===== 0493x19b-fix4 HIGH-SNR OMEGA=0.20 =====\n'
printf 'source=%s\n' "$LATEST_STATE"
printf 'sourceOmega=%s targetOmega=%s Ui=%s\n' "$SOURCE_OMEGA_Z" "$TARGET_OMEGA_Z" "$(python3 -c "print(float('$TARGET_OMEGA_Z')*float('$INNER_RADIUS'))")"
printf 'boostedRestart=%s\n' "$BOOSTED_STATE"
printf 'steps=%s analysisStart=%s summaryEvery=1 dumpEvery=1000\n' "$RUN_STEPS" "$ANALYSIS_START_STEP"
printf 'livevis every=1; reduced record 64x64 every=100; bounceback only\n'
printf '================================================\n\n'

export MPCD_X19B_FIX3_FULL_ANGULAR_AUDIT=0
export MPCD_X19B_FIX2_SRC_ANGULAR_AUDIT=0

ROOT="$ROOT" \
KINETIC_MODE=bounceback \
CASE_LABEL=0493x19b_fix4_bounceback_omega020 \
BASE_RUN_ROOT="$BASE_RUN_ROOT" \
OMEGA_Z="$TARGET_OMEGA_Z" \
STEPS="$RUN_STEPS" \
SEED="$SEED" \
RESTART_STATE="$BOOSTED_STATE" \
RESTART_FROM_STEP="$SOURCE_STEP" \
CLEAN_RUN_ROOT=1 \
SUMMARY_EVERY=1 \
DUMP_STATE_EVERY=1000 \
LIVE_PROGRESS=1 \
LIVE_VIS_ENABLE=1 \
LIVE_VIS_EVERY=1 \
LIVE_VIS_NX=64 \
LIVE_VIS_NY=64 \
FILTERED_RECORDING_ENABLE=1 \
RECORD_ENABLE=true \
RECORD_EVERY=100 \
RECORD_FIELDS=rho,ux,uy \
bash "$ROOT/scripts/run_0493x19b_prescribed_rotating_annulus.sh" || exit 2

OUT="$ROOT/$BASE_RUN_ROOT/fresh/output"
WALLCSV="$OUT/chi_kinetic_boundary_0493x16j.csv"
[[ -s "$WALLCSV" ]] || { echo "[0493x19b-fix4] ERROR missing $WALLCSV" >&2; exit 2; }
header="$(head -n 1 "$WALLCSV")"
for c in x19bInnerTorqueTangentialImpulse x19bOuterTorqueTangentialImpulse x19bInnerTorqueNormalImpulse x19bOuterTorqueNormalImpulse; do
  printf '%s\n' "$header" | grep -q "$c" || { echo "[0493x19b-fix4] ERROR missing diagnostic $c" >&2; exit 2; }
done
rows="$(awk 'END{print NR-1}' "$WALLCSV")"
if [[ "$rows" -lt $((RUN_STEPS-5)) ]]; then
  echo "[0493x19b-fix4] ERROR every-step torque coverage incomplete: rows=$rows expected~$RUN_STEPS" >&2
  exit 2
fi

cat > "$ROOT/$BASE_RUN_ROOT/fresh/highsnr_reference_0493x19b_fix4.txt" <<META
referenceNu=2.3313138152e-04
referenceNuStd=1.0569841665e-05
referenceNuSem=5.2849208326e-06
referenceNuSeeds=4
tgMode=2,2
tgLambda=0.25
tgGrid=128x128
tgCellSize=0.00390625
sourceOmega=$SOURCE_OMEGA_Z
targetOmega=$TARGET_OMEGA_Z
analysisStartStep=$ANALYSIS_START_STEP
sourceState=$LATEST_STATE
boostedState=$BOOSTED_STATE
META
sha256sum "$LATEST_STATE" "$BOOSTED_STATE" > "$ROOT/$BASE_RUN_ROOT/fresh/restart_sha256_0493x19b_fix4.txt"

echo "[0493x19b-fix4] COMPLETE output=$OUT"
echo "[0493x19b-fix4] MATLAB: cd matlab; results = analyze_0493x19b_fix4_highsnr_omega020;"
