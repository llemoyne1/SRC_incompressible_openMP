#!/usr/bin/env bash
# Matched x19b pair: same geometry/seed, specular control then bounceback.
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT" || exit $?
PAIR_ROOT="${PAIR_ROOT:-runs/0493x19b_prescribed_rotating_annulus_pair}"
for kinetic in specular bounceback; do
  echo "[0493x19b-pair] starting $kinetic"
  KINETIC_MODE="$kinetic" \
  BASE_RUN_ROOT="$PAIR_ROOT/$kinetic" \
  CLEAN_RUN_ROOT="${CLEAN_RUN_ROOT:-1}" \
  LIVE_PROGRESS="${LIVE_PROGRESS:-1}" \
  bash scripts/run_0493x19b_prescribed_rotating_annulus.sh || exit $?
done
echo "[0493x19b-pair] COMPLETE root=$PAIR_ROOT"
