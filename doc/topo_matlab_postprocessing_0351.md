# 0351-topo: MATLAB post-processing plots

This patch starts the MATLAB post-processing layer for the topology/Darcy
benchmark branch.  It does not modify the solver and requires no recompilation.

## MATLAB functions

```text
matlab/topo/plot_topo_naca_polar_proxy_0351.m
matlab/topo/plot_topo_channel_shape_comparison_0351.m
```

## Wrapper

```text
scripts/run_matlab_topo_plots_0351.sh
```

The wrapper reads, by default:

```text
runs/topo_darcy_naca_sweep_0349/naca_polar_proxy_0350.csv
runs/topo_darcy_channel_shapes_0349/channel_shapes_0349_summary.csv
```

and writes figures and compact CSV files to:

```text
runs/topo_matlab_plots_0351/
```

## Manual MATLAB use

```matlab
addpath(genpath('matlab'));

plot_topo_naca_polar_proxy_0351( ...
    'runs/topo_darcy_naca_sweep_0349/naca_polar_proxy_0350.csv', ...
    'OutputDir', 'runs/topo_matlab_plots_0351', ...
    'ShowFigures', true);

plot_topo_channel_shape_comparison_0351( ...
    'runs/topo_darcy_channel_shapes_0349/channel_shapes_0349_summary.csv', ...
    'OutputDir', 'runs/topo_matlab_plots_0351', ...
    'ShowFigures', true);
```

## Non-interactive run

```bash
SHOW_FIGURES=false \
POLAR_CSV=runs/topo_darcy_naca_sweep_0349/naca_polar_proxy_0350.csv \
SHAPES_SUMMARY=runs/topo_darcy_channel_shapes_0349/channel_shapes_0349_summary.csv \
OUT_DIR=runs/topo_matlab_plots_0351 \
bash scripts/run_matlab_topo_plots_0351.sh
```

Expected outputs include PNG/PDF figures for:

- NACA lift proxy vs angle of attack;
- NACA drag proxy vs angle of attack;
- NACA lift/drag proxy vs angle of attack;
- NACA Darcy power vs angle of attack;
- channel-shape drag, power, and lift comparisons.
