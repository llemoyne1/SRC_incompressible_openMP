#!/usr/bin/env bash
# Analysis-only review. No build, no simulation, no solver modification.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CAMPAIGN_ROOT="${CAMPAIGN_ROOT:-runs/0493x21e_article_capillary_radius_s10000}"
python3 "$ROOT/scripts/analyze_0493x21e_fix3_article_capillary_review.py" \
  --repo "$ROOT" \
  --campaign-root "$CAMPAIGN_ROOT"
