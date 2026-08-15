#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT"

[[ -x scripts/run_0493x8d_q6gf_poiseuille_chi.sh ]] || {
  echo "[0493x8e-sweep] ERROR missing x8d chi runner" >&2; exit 2; }

CAL_ROOT="${CAL_ROOT:-runs/0493x8e_q6gf_tg_viscosity}"
CAL_JSON="$CAL_ROOT/analysis/q6gf_tg_ensemble_0493x8e.json"
if [[ -z "${NU_DESIGN:-}" ]]; then
  if [[ -f "$CAL_JSON" ]]; then
    NU_DESIGN="$(python3 - "$CAL_JSON" <<'PY'
import json,sys
print("{:.17g}".format(float(json.load(open(sys.argv[1]))["nuMean"])))
PY
)"
  else
    NU_DESIGN=0.00070604
    echo "[0493x8e-sweep] NOTE using x8d solid-wall fallback nu=$NU_DESIGN"
  fi
fi

RUN_ROOT_BASE="${RUN_ROOT_BASE:-runs/0493x8e_q6gf_darcy_alpha_sweep}"
TARGET_UC="${TARGET_UC:-0.1064}"
A_CELL=0.00390625
H=0.25
S=0.0625
DT=0.002
STEPS="${STEPS:-20000}"
SUMMARY_EVERY="${SUMMARY_EVERY:-100}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-1000}"
LIVE_PROGRESS="${LIVE_PROGRESS:-1}"
CASES="${CASES:-ellB4 ellB2 ellB1 ellB0p5 alpha4000}"

mkdir -p "$RUN_ROOT_BASE"
echo 'caseName,targetEllBOverA,alpha,alphaDt,bodyAx,nuDesign,targetUc' \
  > "$RUN_ROOT_BASE/sweep_manifest_0493x8e.csv"

case_values() {
python3 - "$1" "$NU_DESIGN" "$A_CELL" "$H" "$S" "$DT" "$TARGET_UC" <<'PY'
import math,sys
name=sys.argv[1]; nu,a,H,S,dt,U=map(float,sys.argv[2:])
if name.startswith("ellB"):
    q=float(name[4:].replace("p","."))
    alpha=nu/(q*a)**2
else:
    q=math.sqrt(nu/4000.0)/a
    alpha=4000.0
k=math.sqrt(alpha/nu); x=k*S/2
coth=1.0+2.0*math.exp(-2*x) if x>30 else math.cosh(x)/math.sinh(x)
coef=H*H/(8*nu)+1/alpha+H/(2*nu*k)*coth
ax=U/coef
uI=ax/alpha+ax*H/(2*nu*k)*coth
umean=ax*H*H/(12*nu)+uI
print(f"{q:.17g} {alpha:.17g} {alpha*dt:.17g} {ax:.17g} {uI:.17g} {umean:.17g}")
PY
}

echo "[0493x8e-sweep] NU_DESIGN=$NU_DESIGN"
for c in $CASES; do
  read -r ell alpha alphadt ax ui umean <<< "$(case_values "$c")"
  echo "[0493x8e-sweep] $c ellB/a=$ell alpha=$alpha alphaDt=$alphadt ax=$ax"
  printf '%s,%s,%s,%s,%s,%s,%s\n' \
    "$c" "$ell" "$alpha" "$alphadt" "$ax" "$NU_DESIGN" "$TARGET_UC" \
    >> "$RUN_ROOT_BASE/sweep_manifest_0493x8e.csv"

  BASE_RUN_ROOT="$RUN_ROOT_BASE/$c" \
  ALPHA="$alpha" BODY_AX="$ax" \
  REFERENCE_NU="$NU_DESIGN" REFERENCE_CS=0.35459 \
  REFERENCE_UCHAR="$TARGET_UC" REFERENCE_L=0.24 \
  STEPS="$STEPS" SUMMARY_EVERY="$SUMMARY_EVERY" \
  DUMP_STATE_EVERY="$DUMP_STATE_EVERY" \
  LIVE_PROGRESS="$LIVE_PROGRESS" CLEAN_RUN_ROOT=1 \
  bash scripts/run_0493x8d_q6gf_poiseuille_chi.sh
done

echo "[0493x8e-sweep] MATLAB:"
echo "addpath('matlab');"
echo "out=analyze_0493x8e_q6gf_darcy_alpha_sweep('$RUN_ROOT_BASE','nuReference',$NU_DESIGN);"
