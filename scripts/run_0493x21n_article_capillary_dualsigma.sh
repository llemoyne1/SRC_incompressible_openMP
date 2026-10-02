#!/usr/bin/env bash
# 0493x21n: article-only dual-sigma capillary finalization.
# Uses existing x21e + x21g + x21i outputs. No solver run, no compilation.
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PYTHON_BIN="${PYTHON_BIN:-python3}"

"$PYTHON_BIN" "$ROOT/scripts/make_article_capillary_characterization_dualsigma.py" --repo "$ROOT" --preflight
rc=$?
if [ "$rc" -ne 0 ]; then
  echo "[0493x21n] preflight FAILED rc=$rc" >&2
  exit "$rc"
fi

"$PYTHON_BIN" "$ROOT/scripts/make_article_capillary_characterization_dualsigma.py" --repo "$ROOT"
rc=$?
if [ "$rc" -ne 0 ]; then
  echo "[0493x21n] generation FAILED rc=$rc" >&2
  exit "$rc"
fi

echo "[0493x21n] DONE"
echo "[0493x21n] package: $ROOT/runs/0493x21n_article_capillary_dualsigma/article_capillary_outputs_v3_dualsigma.zip"
