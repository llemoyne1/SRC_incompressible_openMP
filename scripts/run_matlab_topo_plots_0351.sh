#!/usr/bin/env bash
set -euo pipefail

# 0351/topo: MATLAB plotting wrapper for Darcy/NACA postprocessing.
# No solver changes.  Requires MATLAB available in PATH.

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

POLAR_CSV="${POLAR_CSV:-runs/topo_darcy_naca_sweep_0349/naca_polar_proxy_0350.csv}"
SHAPES_SUMMARY="${SHAPES_SUMMARY:-runs/topo_darcy_channel_shapes_0349/channel_shapes_0349_summary.csv}"
OUT_DIR="${OUT_DIR:-runs/topo_matlab_plots_0351}"
SHOW_FIGURES="${SHOW_FIGURES:-false}"

mkdir -p "$OUT_DIR"

if ! command -v matlab >/dev/null 2>&1; then
  echo "[0351-matlab] ERROR: matlab command not found in PATH" >&2
  exit 127
fi

matlab -batch "addpath(genpath('matlab')); \
  if exist('$POLAR_CSV','file'), plot_topo_naca_polar_proxy_0351('$POLAR_CSV','OutputDir','$OUT_DIR','ShowFigures',$SHOW_FIGURES); else, warning('Missing POLAR_CSV: $POLAR_CSV'); end; \
  if exist('$SHAPES_SUMMARY','file'), plot_topo_channel_shape_comparison_0351('$SHAPES_SUMMARY','OutputDir','$OUT_DIR','ShowFigures',$SHOW_FIGURES); else, warning('Missing SHAPES_SUMMARY: $SHAPES_SUMMARY'); end;"

echo "[0351-matlab] outputDir=$OUT_DIR"
find "$OUT_DIR" -maxdepth 1 -type f | sort
