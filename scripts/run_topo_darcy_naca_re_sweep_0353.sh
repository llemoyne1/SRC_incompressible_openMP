#!/usr/bin/env bash
set -euo pipefail

# 0353/topo: higher-resolution NACA sweep using Poiseuille-calibrated nu_eff.
# No solver change.  The script generates chi_file NACA fields, runs the existing
# CUDA Darcy/Brinkman benchmark path, computes 0348b window statistics, and builds
# a 0350 polar-proxy CSV.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

NACA_CODE="${NACA_CODE:-0012}"
AOAS="${AOAS:--14 -12 -10 -8 -6 -4 -2 0 2 4 6 8 10 12 14}"

Lx="${Lx:-1.5}"
Ly="${Ly:-0.4}"
NX="${NX:-600}"
NY="${NY:-160}"
GAMMA="${GAMMA:-10}"
KBT="${KBT:-0.01}"
DT="${DT:-0.0005}"
U0="${U0:-1.0}"
CHORD="${CHORD:-0.22}"
AIRFOIL_CX="${AIRFOIL_CX:-0.55}"
AIRFOIL_CY="${AIRFOIL_CY:-0.20}"
DARCY_INTERFACE_WIDTH="${DARCY_INTERFACE_WIDTH:-0.004}"
DARCY_ALPHA_MAX="${DARCY_ALPHA_MAX:-320}"
DARCY_Q="${DARCY_Q:-0.1}"

NU_EFF_REF="${NU_EFF_REF:-0.002327998935968954}"
RE_EFF=$(python3 - <<PY
nu=float("${NU_EFF_REF}")
u=float("${U0}")
c=float("${CHORD}")
print("{:.12g}".format(u*c/nu))
PY
)

STEPS="${STEPS:-2500}"
TOPO_BENCHMARK_EVERY="${TOPO_BENCHMARK_EVERY:-20}"
TAIL_FRACTION="${TAIL_FRACTION:-0.5}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-0}"
FORCE_REBUILD="${FORCE_REBUILD:-0}"
BIN="${BIN:-build/src_mpcd_base_cuda_topo_0348a}"
SEED_BASE="${SEED_BASE:-1703500}"
LIFT_SIGN="${LIFT_SIGN:--1}"
DRAG_SIGN="${DRAG_SIGN:-1}"

TAG_PREFIX="${TAG_PREFIX:-topo_darcy_naca_re_sweep_0353}"
RUN_ROOT="runs/${TAG_PREFIX}"
CHI_DIR="${RUN_ROOT}/chi"
mkdir -p "$CHI_DIR" "${RUN_ROOT}/logs"

summary="${RUN_ROOT}/naca_re_sweep_0353_summary.csv"
echo "naca,aoaDeg,U0,chord,nuEffRef,ReEff,kBT,gamma,Nx,Ny,steps,chiFile,benchmarkCsv,windowStatsCsv" > "$summary"

echo "[0353-naca-re] NACA=${NACA_CODE} AOAS=${AOAS}"
echo "[0353-naca-re] grid=${NX}x${NY} gamma=${GAMMA} Np~$((NX*NY*GAMMA)) kBT=${KBT} U0=${U0} chord=${CHORD} nuEffRef=${NU_EFF_REF} ReEff=${RE_EFF}"

for aoa in $AOAS; do
  if [[ "$aoa" == -* ]]; then
    aoa_tag="am${aoa#-}"
  else
    aoa_tag="a${aoa}"
  fi
  aoa_tag="${aoa_tag//./p}"
  tag="${TAG_PREFIX}_${NACA_CODE}_${aoa_tag}"
  chi_file="${CHI_DIR}/naca${NACA_CODE}_aoa${aoa_tag}_${NX}x${NY}.f32"
  seed=$((SEED_BASE + ${aoa#-} + (aoa < 0 ? 1000 : 0) ))
  # Bash arithmetic cannot parse decimal AoA.  Fall back to deterministic seed
  # based on the loop index when decimal angles are used.
  seed="$(python3 - <<PY
import hashlib
base=int("${SEED_BASE}")
key="${NACA_CODE}_${aoa}"
h=int(hashlib.sha1(key.encode()).hexdigest()[:6], 16)
print(base + h % 100000)
PY
)"

  python3 scripts/generate_topo_chi_field_0345.py \
    --mode naca4_airfoil --out "$chi_file" \
    --Nx "$NX" --Ny "$NY" --Lx "$Lx" --Ly "$Ly" \
    --naca "$NACA_CODE" --chord "$CHORD" \
    --airfoil-cx "$AIRFOIL_CX" --airfoil-cy "$AIRFOIL_CY" \
    --aoa-deg "$aoa" --interface-width "$DARCY_INTERFACE_WIDTH" \
    | tee "${RUN_ROOT}/logs/generate_${NACA_CODE}_${aoa_tag}.log"

  echo "[0353-naca-re] running aoa=$aoa tag=$tag seed=$seed"

  BIN="$BIN" \
  Lx="$Lx" Ly="$Ly" NX="$NX" NY="$NY" GAMMA="$GAMMA" KBT="$KBT" DT="$DT" U0="$U0" SEED="$seed" STEPS="$STEPS" \
  DARCY_CHI_MODE=file DARCY_CHI_FILE="$chi_file" DARCY_CHI_FILE_FORMAT=float32 \
  DARCY_ALPHA_MAX="$DARCY_ALPHA_MAX" DARCY_Q="$DARCY_Q" DARCY_COST_EVERY="$TOPO_BENCHMARK_EVERY" \
  TOPO_BENCHMARK_ENABLE=1 TOPO_BENCHMARK_EVERY="$TOPO_BENCHMARK_EVERY" \
  TOPO_BENCHMARK_FORCE_ENABLE=1 TOPO_BENCHMARK_DRAG_LIFT_ENABLE=1 \
  TOPO_BENCHMARK_FLOW_DIR_X=1 TOPO_BENCHMARK_FLOW_DIR_Y=0 \
  TOPO_BENCHMARK_LIFT_DIR_X=0 TOPO_BENCHMARK_LIFT_DIR_Y=1 \
  LIVE_VIS_ENABLE="$LIVE_VIS_ENABLE" LIVE_VIS_NX="$NX" LIVE_VIS_NY="$NY" \
  FORCE_REBUILD="$FORCE_REBUILD" CLEAN_RUN_ROOT=1 TAG="$tag" \
    bash scripts/run_topo_darcy_brinkman_viz_0343.sh \
    2>&1 | tee "${RUN_ROOT}/logs/run_${NACA_CODE}_${aoa_tag}.log"

  csv="runs/${tag}/output/topo_benchmark_0348.csv"
  stats="runs/${tag}/topo_benchmark_window_stats_0348b.csv"
  python3 scripts/analyze_topo_benchmark_window_0348b.py \
    --csv "$csv" \
    --out "$stats" \
    --tail-fraction "$TAIL_FRACTION" \
    | tee "${RUN_ROOT}/logs/window_${NACA_CODE}_${aoa_tag}.log"

  printf '%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s,%s\n' \
    "$NACA_CODE" "$aoa" "$U0" "$CHORD" "$NU_EFF_REF" "$RE_EFF" "$KBT" "$GAMMA" "$NX" "$NY" "$STEPS" "$chi_file" "$csv" "$stats" >> "$summary"
done

polar="${RUN_ROOT}/naca_re_polar_proxy_0353.csv"
python3 scripts/analyze_topo_naca_polar_proxy_0350.py \
  --summary "$summary" \
  --out "$polar" \
  --lift-sign "$LIFT_SIGN" \
  --drag-sign "$DRAG_SIGN" \
  | tee "${RUN_ROOT}/logs/polar_proxy_0353.log"

# Add calibration columns if the 0350 analyzer did not propagate them.
tmp="${polar}.tmp"
python3 - <<PY
import csv
from pathlib import Path
polar = Path("${polar}")
summary = Path("${summary}")
rows = list(csv.DictReader(polar.open(newline='')))
meta = {}
for r in csv.DictReader(summary.open(newline='')):
    meta[(r['naca'], float(r['aoaDeg']))] = r
extra = ['U0','chord','nuEffRef','ReEff','kBT','gamma','Nx','Ny','steps']
if rows:
    fields = list(rows[0].keys())
    for e in extra:
        if e not in fields:
            fields.append(e)
    for r in rows:
        m = meta.get((r['naca'], float(r['aoaDeg'])), {})
        for e in extra:
            r[e] = m.get(e, r.get(e, ''))
    with Path("${tmp}").open('w', newline='') as f:
        w = csv.DictWriter(f, fieldnames=fields)
        w.writeheader()
        w.writerows(rows)
    Path("${tmp}").replace(polar)
PY

echo "[0353-naca-re] summary=$summary"
echo "[0353-naca-re] polar=$polar"
cat "$polar"
