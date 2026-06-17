#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

POLAR_CSV="${POLAR_CSV:-runs/topo_darcy_naca_re_sweep_0353/naca_re_polar_proxy_0353.csv}"
OUT_DIR="${OUT_DIR:-runs/topo_matlab_plots_0353}"
SHOW_FIGURES="${SHOW_FIGURES:-false}"

MATLAB_BIN="${MATLAB_BIN:-matlab}"

"$MATLAB_BIN" -batch "addpath(genpath('matlab')); plot_topo_naca_re_polar_0353('${POLAR_CSV}', 'OutputDir', '${OUT_DIR}', 'ShowFigures', ${SHOW_FIGURES});"
