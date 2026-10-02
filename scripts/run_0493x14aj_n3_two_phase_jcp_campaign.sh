#!/usr/bin/env bash

ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
RUNNER="$ROOT/scripts/run_0493x14aj_n3_two_phase_jcp.sh"
SEEDS="${SEEDS:-493180 493181 493182}"

if [[ ! -x "$RUNNER" ]]; then
  echo "[0493x14aj-JCP-campaign] ERROR missing/executable runner: $RUNNER" >&2
  exit 2
fi

# The three-seed ensemble is deliberate: the per-particle thermal speed is much
# larger than the coherent interface velocity, so publication metrics must not
# rest on a single thermal realization.  The physical point itself is frozen.
for seed in $SEEDS; do
  echo
  echo "===== 0493x14aj-JCP seed $seed ====="
  if ! SEED="$seed" \
      GAMMA=20 LIQUID_KBT=0.02 GAS_KBT=0.08 \
      LIQUID_MASS=1.0 GAS_MASS=0.1 \
      MODE=3 EPSILON=0.04 RADIUS_CELLS=40 \
      SURFACE_TENSION_SIGMA=2560.0 DT=0.002 STEPS=3000 \
      DUMP_STATE_EVERY=125 SUMMARY_EVERY=10 \
      LIVE_VIS_ENABLE=1 LIVE_VIS_EVERY=1 LIVE_VIS_HOLD_ON_EXIT=0 \
      RECORD_ENABLE=true RECORD_EVERY=100 \
      RESTART=0 \
      bash "$RUNNER"; then
    echo "[0493x14aj-JCP-campaign] ERROR seed $seed failed; ensemble analysis not launched" >&2
    exit 2
  fi
done

echo
if command -v matlab >/dev/null 2>&1; then
  seedvec="$(printf '%s ' $SEEDS | sed 's/ /,/g; s/,$//')"
  if ! matlab -batch "cd('$ROOT/matlab'); analyze_0493x14aj_n3_two_phase_jcp('../runs',[$seedvec]);"; then
    echo "[0493x14aj-JCP-campaign] ERROR MATLAB analysis failed" >&2
    exit 2
  fi
else
  echo "[0493x14aj-JCP-campaign] MATLAB not found in PATH. Run analysis manually:"
  echo "  cd '$ROOT/matlab'"
  echo "  matlab -batch \"analyze_0493x14aj_n3_two_phase_jcp('../runs')\""
fi
