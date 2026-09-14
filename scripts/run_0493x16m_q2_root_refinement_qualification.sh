#!/usr/bin/env bash
# 0493x16m — complete material-wall qualification after chi-only Q2 root fix.
# Four runs are inherited from x16l; x16m analysis gates penetration over ALL steps.
set -u
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
cd "$ROOT" || exit $?
BASE="${BASE_RUN_ROOT:-runs/0493x16m_q2_root_refinement_qualification}"
STEPS="${STEPS:-600}"

echo "[0493x16m] root=$BASE steps=$STEPS q2Root=bisection targetPathCells=1e-8"
set +e
BASE_RUN_ROOT="$BASE" STEPS="$STEPS" \
  bash scripts/run_0493x16l_chi_penetration_qualification.sh
run_rc=$?
set -e
# x16l may return 3 solely because its old analyzer reviews a physics gate.
# Any other non-zero value is treated as an execution failure.
if (( run_rc != 0 && run_rc != 3 )); then
  echo "[0493x16m] ERROR underlying run failed rc=$run_rc" >&2
  exit "$run_rc"
fi

python3 scripts/analyze_0493x16m_q2_root_refinement.py "$BASE"
rc=$?
if (( rc == 0 )); then
  echo "[0493x16m] PASS root=$BASE"
else
  echo "[0493x16m] REVIEW root=$BASE analyzer_rc=$rc" >&2
fi
exit "$rc"
