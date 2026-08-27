#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"; cd "$ROOT"
BRANCH="${BRANCH:-both}"
case "$BRANCH" in
 H|h|Hgamma) bash scripts/run_0493x13c_H_gamma_multiseed.sh;;
 C|c|Cstat) bash scripts/run_0493x13c_C_longitudinal_statistics.sh;;
 both)
   bash scripts/run_0493x13c_H_gamma_multiseed.sh
   bash scripts/run_0493x13c_C_longitudinal_statistics.sh
   ;;
 *) echo "usage: BRANCH=H|C|both $0" >&2; exit 2;;
esac
