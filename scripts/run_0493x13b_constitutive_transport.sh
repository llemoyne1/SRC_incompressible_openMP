#!/usr/bin/env bash
set -euo pipefail
ROOT="${ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"; cd "$ROOT"
STAGES="${STAGES:-H,C}"
case ",$STAGES," in *,H,*) bash scripts/run_0493x13b_H_constitutive_shear.sh ;; esac
case ",$STAGES," in *,C,*) CLEAN_ROOT="${CLEAN_ROOT_C:-1}" bash scripts/run_0493x13b_C_longitudinal_response.sh ;; esac
python3 scripts/analyze_0493x13b_constitutive_transport.py --campaign-root "${CAMPAIGN_ROOT:-runs/0493x13b_constitutive_transport}" --repo-root "$ROOT"
