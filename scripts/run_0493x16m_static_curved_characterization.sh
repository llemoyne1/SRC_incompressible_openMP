#!/usr/bin/env bash
# 0493x16m characterization: fixed curved chi wall (peak x16i shape), rest vs boost.
# No time-dependent deformation: isolates spatial curvature from deforming-wall timing.
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"
BASE="${BASE_RUN_ROOT:-runs/0493x16m_static_curved_characterization}"
STEPS="${STEPS:-800}"
BURN_IN_STEPS="${BURN_IN_STEPS:-200}"
DT="${DT:-0.002}"
BOOST_UX="${BOOST_UX:-0.08}"
DEFORM_AMPLITUDE_CELLS="${DEFORM_AMPLITUDE_CELLS:-0.75}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-1}"
SEED="${SEED:-4931610}"

if [[ ! -x scripts/run_0493x16j_chi_kinetic_specular_case.sh ]]; then
  echo "[0493x16m-static-curve] ERROR missing x16j case runner" >&2; exit 2
fi
if ! grep -q 'q2Root=x16m-bisection-1e-8cell' src/cuda_q6_resident_0400.cu; then
  echo "[0493x16m-static-curve] ERROR x16m Q2 root refinement not present" >&2; exit 2
fi
if ! grep -q 'SRC_X16I_STATIC_CURVED_0493X16M' src/cuda_chi_solid_0493x16e.cu; then
  echo "[0493x16m-static-curve] ERROR static-curved diagnostic source support absent" >&2; exit 2
fi

rm -rf "$BASE"
mkdir -p "$BASE"
cat > "$BASE/characterization_meta.txt" <<META
purpose=isolate_spatial_curvature_from_time_dependent_deformation
shape=x_center(y)=X+A*sin(2*pi*y/Ly)
shapeTimeDependence=none
amplitudeCells=$DEFORM_AMPLITUDE_CELLS
fluidDt=$DT
steps=$STEPS
burnInSteps=$BURN_IN_STEPS
measurementSteps=$((STEPS-BURN_IN_STEPS))
frames=rest,boost
boostUx=$BOOST_UX
q2Root=x16m-bisection-1e-8cell
penetrationDiagnostic=x16l_poststream_Q2
physicsChange=test_only_static_shape_switch
META

export SRC_X16I_STATIC_CURVED_0493X16M=1
trap 'unset SRC_X16I_STATIC_CURVED_0493X16M' EXIT

for frame in rest boost; do
  if [[ "$frame" == "rest" ]]; then ux=0.0; else ux="$BOOST_UX"; fi
  case_root="$BASE/$frame"
  label="0493x16m_static_curved_${frame}"
  echo "[0493x16m-static-curve] frame=$frame Ux=$ux A/h=$DEFORM_AMPLITUDE_CELLS steps=$STEPS burnIn=$BURN_IN_STEPS dt=$DT"
  BASE_RUN_ROOT="$case_root" \
  CASE_LABEL="$label" \
  COMMON_UX="$ux" \
  DEFORMABLE=1 \
  DEFORM_AMPLITUDE_CELLS="$DEFORM_AMPLITUDE_CELLS" \
  DEFORM_PERIOD_STEPS=400 \
  DT="$DT" \
  STEPS="$STEPS" \
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
  [[ -s "$out/chi_penetration_0493x16l.csv" ]] || { echo "[0493x16m-static-curve] ERROR missing penetration CSV frame=$frame" >&2; exit 2; }
  [[ -s "$out/chi_kinetic_boundary_0493x16j.csv" ]] || { echo "[0493x16m-static-curve] ERROR missing kinetic CSV frame=$frame" >&2; exit 2; }
  [[ -s "$out/chi_solid_dynamics_0493x16a.csv" ]] || { echo "[0493x16m-static-curve] ERROR missing solid CSV frame=$frame" >&2; exit 2; }
  grep -q 'q2Root=x16m-bisection-1e-8cell' "$log" || { echo "[0493x16m-static-curve] ERROR x16m runtime marker absent frame=$frame" >&2; exit 2; }
  python3 - "$out/chi_solid_dynamics_0493x16a.csv" <<'PY'
import csv, sys
p=sys.argv[1]
with open(p,newline='') as f:
    r=next(csv.DictReader(f))
assert int(float(r['prescribedDeformable0493x16i'])) == 1, 'prescribed deformable marker not active'
assert float(r['deformAmplitude0493x16i']) > 0.0, 'zero static curvature amplitude'
assert abs(float(r['deformOmega0493x16i'])) <= 1e-30, 'static curve omega is not zero'
PY
done

python3 scripts/analyze_0493x16m_static_curved_characterization.py "$BASE" "$BURN_IN_STEPS"
