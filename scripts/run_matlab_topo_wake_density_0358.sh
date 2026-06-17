#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
RUN_ROOT="${RUN_ROOT:-runs/topo_vk_0356f_darcy5000_matched}"
OUT_DIR="${OUT_DIR:-${RUN_ROOT}/analysis}"
SHOW_FIGURES="${SHOW_FIGURES:-false}"
MATLAB_BIN="${MATLAB_BIN:-matlab}"
"$MATLAB_BIN" -batch "addpath(genpath('matlab')); analyze_topo_wake_density_0358('${RUN_ROOT}', 'OutputDir', '${OUT_DIR}', 'MakePlots', true, 'ShowFigures', ${SHOW_FIGURES});"
