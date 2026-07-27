#!/usr/bin/env bash
set -euo pipefail

RUN_ROOT=${RUN_ROOT:-runs/0493k_tg_binary_64_m2_pilot_1500}
SEED=${SEED:-493101}
SCENARIO=${SCENARIO:-binary_species}
RUN_MODES=${RUN_MODES:-"src src-resampling"}
STEPS_LIST=${STEPS_LIST:-"0 200 400 800 1500"}
NX=${NX:-64}
NY=${NY:-64}
TG_MODE=${TG_MODE:-2}
RADIAL_BINS=${RADIAL_BINS:-12}
OUTPUT_DIR=${OUTPUT_DIR:-$RUN_ROOT}

read -r -a mode_array <<< "$RUN_MODES"

python3 scripts/analyze_0493l_particle_weight_transport.py \
  --root "$RUN_ROOT" \
  --seed "$SEED" \
  --scenario "$SCENARIO" \
  --modes "${mode_array[@]}" \
  --steps "$STEPS_LIST" \
  --nx "$NX" \
  --ny "$NY" \
  --tg-mode "$TG_MODE" \
  --radial-bins "$RADIAL_BINS" \
  --output-dir "$OUTPUT_DIR"
