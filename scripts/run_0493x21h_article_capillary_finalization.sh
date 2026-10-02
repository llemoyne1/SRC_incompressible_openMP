#!/usr/bin/env bash
# 0493x21h: article-only finalization from frozen x21e + x21g outputs.
# No solver run, no compilation, no C++/CUDA modification.

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PYTHON_BIN="${PYTHON_BIN:-python3}"

"$PYTHON_BIN" "$ROOT/scripts/make_article_capillary_characterization.py" --repo "$ROOT" --preflight
rc=$?
if [ "$rc" -ne 0 ]; then
  echo "[0493x21h] preflight FAILED rc=$rc" >&2
  exit "$rc"
fi

"$PYTHON_BIN" "$ROOT/scripts/make_article_capillary_characterization.py" --repo "$ROOT"
rc=$?
if [ "$rc" -ne 0 ]; then
  echo "[0493x21h] generation FAILED rc=$rc" >&2
  exit "$rc"
fi

echo "[0493x21h] DONE"
echo "[0493x21h] package: $ROOT/runs/0493x21h_article_capillary_outputs_v2/article_capillary_outputs_v2.zip"
