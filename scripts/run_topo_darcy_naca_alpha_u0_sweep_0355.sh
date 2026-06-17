#!/usr/bin/env bash
set -euo pipefail

# 0355/topo: NACA sensitivity sweep over Darcy alphaMax and U0.
# This script reuses the calibrated 0353 NACA sweep runner, then combines all
# polar-proxy CSV files into a single table for MATLAB analysis.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

ALPHAS="${ALPHAS:-320 640 1000}"
U0S="${U0S:-1.0 1.5}"
AOAS="${AOAS:--14 -8 0 8 14}"

NX="${NX:-600}"
NY="${NY:-160}"
GAMMA="${GAMMA:-10}"
KBT="${KBT:-0.01}"
DT="${DT:-0.0005}"
CHORD="${CHORD:-0.22}"
NU_EFF_REF="${NU_EFF_REF:-0.002327998935968954}"
STEPS="${STEPS:-2000}"
TOPO_BENCHMARK_EVERY="${TOPO_BENCHMARK_EVERY:-20}"
TAIL_FRACTION="${TAIL_FRACTION:-0.5}"
LIVE_VIS_ENABLE="${LIVE_VIS_ENABLE:-0}"
DUMP_STATE_EVERY="${DUMP_STATE_EVERY:-0}"
FORCE_REBUILD="${FORCE_REBUILD:-0}"
BIN="${BIN:-build/src_mpcd_base_cuda_topo_0348a}"

RUN_ROOT="${RUN_ROOT:-runs/topo_darcy_naca_alpha_u0_sweep_0355}"
mkdir -p "$RUN_ROOT/logs"

manifest="$RUN_ROOT/naca_alpha_u0_sweep_0355_manifest.csv"
combined="$RUN_ROOT/naca_alpha_u0_sweep_0355_combined.csv"
echo "alphaMax,U0,tagPrefix,polarCsv" > "$manifest"

echo "[0355-alpha-u0] ALPHAS=${ALPHAS}"
echo "[0355-alpha-u0] U0S=${U0S}"
echo "[0355-alpha-u0] AOAS=${AOAS}"
echo "[0355-alpha-u0] grid=${NX}x${NY} gamma=${GAMMA} kBT=${KBT} chord=${CHORD} nuEffRef=${NU_EFF_REF}"

for alpha in $ALPHAS; do
  alpha_tag="${alpha//./p}"
  for u in $U0S; do
    u_tag="${u//./p}"
    tag="topo_darcy_naca_alpha_u0_sweep_0355_alpha${alpha_tag}_u${u_tag}"
    echo "[0355-alpha-u0] running alphaMax=$alpha U0=$u tag=$tag"

    BIN="$BIN" \
    TAG_PREFIX="$tag" \
    NX="$NX" NY="$NY" GAMMA="$GAMMA" KBT="$KBT" DT="$DT" \
    U0="$u" CHORD="$CHORD" NU_EFF_REF="$NU_EFF_REF" \
    AOAS="$AOAS" STEPS="$STEPS" TOPO_BENCHMARK_EVERY="$TOPO_BENCHMARK_EVERY" TAIL_FRACTION="$TAIL_FRACTION" \
    DARCY_ALPHA_MAX="$alpha" \
    LIVE_VIS_ENABLE="$LIVE_VIS_ENABLE" DUMP_STATE_EVERY="$DUMP_STATE_EVERY" \
    FORCE_REBUILD="$FORCE_REBUILD" \
      bash scripts/run_topo_darcy_naca_re_sweep_0353.sh \
      2>&1 | tee "$RUN_ROOT/logs/run_alpha${alpha_tag}_u${u_tag}.log"

    polar="runs/${tag}/naca_re_polar_proxy_0353.csv"
    if [[ ! -f "$polar" ]]; then
      echo "[0355-alpha-u0] ERROR: missing polar CSV $polar" >&2
      exit 3
    fi
    printf '%s,%s,%s,%s\n' "$alpha" "$u" "$tag" "$polar" >> "$manifest"
  done
done

python3 - "$manifest" "$combined" <<'PY'
import csv, sys
from pathlib import Path

manifest = Path(sys.argv[1])
combined = Path(sys.argv[2])
rows = []
fields = []
for m in csv.DictReader(manifest.open(newline='')):
    polar = Path(m['polarCsv'])
    with polar.open(newline='') as f:
        for r in csv.DictReader(f):
            r['alphaMax'] = m['alphaMax']
            r['U0_sweep'] = m['U0']
            r['tagPrefix'] = m['tagPrefix']
            r['sourcePolarCsv'] = str(polar)
            rows.append(r)
            for k in r.keys():
                if k not in fields:
                    fields.append(k)
preferred = ['alphaMax','U0_sweep','naca','aoaDeg','dragProxy_mean','dragProxy_std','liftProxy_mean','liftProxy_std','liftOverDragProxy','absLiftOverAbsDrag','darcyPower_mean','darcyPower_std','solidLeakOverSpeed_mean','ReEff','U0','chord','nuEffRef','kBT','gamma','Nx','Ny','steps','tagPrefix','sourcePolarCsv']
ordered = [f for f in preferred if f in fields] + [f for f in fields if f not in preferred]
combined.parent.mkdir(parents=True, exist_ok=True)
with combined.open('w', newline='') as f:
    w = csv.DictWriter(f, fieldnames=ordered)
    w.writeheader()
    w.writerows(rows)
print(f"[0355-alpha-u0] wrote {combined} rows={len(rows)}")
PY

echo "[0355-alpha-u0] manifest=$manifest"
echo "[0355-alpha-u0] combined=$combined"
cat "$combined"
