#!/usr/bin/env bash
# 0493x16m characterization: hold MPCD dt/fluid fixed, slow only prescribed wall deformation.
# Same amplitude and same number of deformation cycles for period factors 1,2,4.
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"
BASE="${BASE_RUN_ROOT:-runs/0493x16m_wall_motion_rate_characterization}"
DT_FIXED="${DT_FIXED:-0.002}"
BASE_PERIOD_STEPS="${BASE_PERIOD_STEPS:-400}"
CYCLES_NUM="${CYCLES_NUM:-3}"
CYCLES_DEN="${CYCLES_DEN:-2}"
BOOST_UX="${BOOST_UX:-0.08}"
DEFORM_AMPLITUDE_CELLS="${DEFORM_AMPLITUDE_CELLS:-0.75}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
SEED="${SEED:-4931610}"

if [[ ! -x scripts/run_0493x16j_chi_kinetic_specular_case.sh ]]; then
  echo "[0493x16m-char] ERROR missing x16j case runner" >&2; exit 2
fi
if ! grep -q 'q2Root=x16m-bisection-1e-8cell' src/cuda_q6_resident_0400.cu; then
  echo "[0493x16m-char] ERROR x16m chi-only Q2 root refinement not present" >&2; exit 2
fi
if (( BASE_PERIOD_STEPS <= 4 || CYCLES_NUM <= 0 || CYCLES_DEN <= 0 )); then
  echo "[0493x16m-char] ERROR invalid period/cycle settings" >&2; exit 2
fi

mkdir -p "$BASE"
cat > "$BASE/characterization_meta.txt" <<META
purpose=characterize_residual_deformable_wall_penetration_vs_wall_motion_per_mpcd_step
fluidDtFixed=$DT_FIXED
fluidCollisionIntervalFixed=true
boostUx=$BOOST_UX
deformAmplitudeCells=$DEFORM_AMPLITUDE_CELLS
basePeriodSteps=$BASE_PERIOD_STEPS
cycles=$CYCLES_NUM/$CYCLES_DEN
periodFactors=1,2,4
physicsChanges=none
META

echo "[0493x16m-char] root=$BASE dt_fixed=$DT_FIXED amplitudeCells=$DEFORM_AMPLITUDE_CELLS cycles=$CYCLES_NUM/$CYCLES_DEN"

for factor in 1 2 4; do
  period=$((BASE_PERIOD_STEPS * factor))
  prod=$((period * CYCLES_NUM))
  if (( prod % CYCLES_DEN != 0 )); then
    echo "[0493x16m-char] ERROR period*$CYCLES_NUM must be divisible by $CYCLES_DEN (period=$period)" >&2
    exit 2
  fi
  steps=$((prod / CYCLES_DEN))
  case_root="$BASE/rate_x${factor}"
  label="0493x16m_char_rate_x${factor}"
  echo "[0493x16m-char] factor=$factor periodSteps=$period steps=$steps dt=$DT_FIXED"
  BASE_RUN_ROOT="$case_root" \
  CASE_LABEL="$label" \
  COMMON_UX="$BOOST_UX" \
  DEFORMABLE=1 \
  DEFORM_AMPLITUDE_CELLS="$DEFORM_AMPLITUDE_CELLS" \
  DEFORM_PERIOD_STEPS="$period" \
  DT="$DT_FIXED" \
  STEPS="$steps" \
  SEED="$SEED" \
  SUMMARY_EVERY=1 \
  DUMP_STATE_EVERY=0 \
  CLEAN_RUN_ROOT=1 \
  LIVE_VIS_ENABLE="$LIVE_VIS_ENABLE" \
  FILTERED_RECORDING_ENABLE=0 \
  RECORD_ENABLE=false \
  bash scripts/run_0493x16j_chi_kinetic_specular_case.sh

  out="$case_root/fresh/output"
  log="$case_root/fresh/logs/${label}.log"
  [[ -s "$out/chi_penetration_0493x16l.csv" ]] || { echo "[0493x16m-char] ERROR missing penetration CSV factor=$factor" >&2; exit 2; }
  [[ -s "$out/chi_kinetic_boundary_0493x16j.csv" ]] || { echo "[0493x16m-char] ERROR missing kinetic CSV factor=$factor" >&2; exit 2; }
  grep -q 'q2Root=x16m-bisection-1e-8cell' "$log" || { echo "[0493x16m-char] ERROR x16m runtime marker absent factor=$factor" >&2; exit 2; }
done

python3 scripts/analyze_0493x16m_wall_motion_rate_characterization.py "$BASE"
