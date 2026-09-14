#!/usr/bin/env bash
# 0493x17a: same user-facing chi input and x16j public switch, but the material
# wall backend is a persistent Lagrangian edge mesh extracted once at chi=0.5.
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT" || exit $?
BASE_RUN_ROOT="${BASE_RUN_ROOT:-runs/0493x17a_lagrangian_boundary}"
CASE_LABEL="${CASE_LABEL:-0493x17a_lagrangian_boundary}"
BASE_RUN_ROOT="$BASE_RUN_ROOT" CASE_LABEL="$CASE_LABEL" \
  bash scripts/run_0493x16j_chi_kinetic_specular_case.sh || exit $?
RUN="$BASE_RUN_ROOT/fresh"
LOG="$RUN/logs/${CASE_LABEL}.log"
OUT="$RUN/output"
grep -q 'backend=x17a-lagrangian-edge-mesh' "$LOG" || { echo '[0493x17a] ERROR runtime backend marker absent' >&2; exit 2; }
grep -q 'collision=space-time-moving-segment-quadratic' "$LOG" || { echo '[0493x17a] ERROR space-time collision marker absent' >&2; exit 2; }
[[ -s "$OUT/chi_lagrangian_mesh_0493x17a.csv" ]] || { echo '[0493x17a] ERROR missing initial Lagrangian mesh CSV' >&2; exit 2; }
[[ -s "$OUT/chi_lagrangian_mesh_0493x17a.txt" ]] || { echo '[0493x17a] ERROR missing mesh summary' >&2; exit 2; }
grep -q '^chiReextract=never$' "$OUT/chi_lagrangian_mesh_0493x17a.txt" || { echo '[0493x17a] ERROR mesh authority marker absent' >&2; exit 2; }
echo "[0493x17a] COMPLETE run=$RUN"
