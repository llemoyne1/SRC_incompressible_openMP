# 0355-topo: NACA alphaMax / U0 sensitivity sweep

This patch studies why the NACA drag proxy is too flat compared with the
normalised NACA/Ladson reference curve.

It reuses the 0353 calibrated sweep runner and varies:

```text
DARCY_ALPHA_MAX
U0
```

## Default sweep

```text
ALPHAS = 320 640 1000
U0S    = 1.0 1.5
AOAS   = -14 -8 0 8 14
```

This keeps the first sensitivity run moderate: 30 NACA cases.

## Run

```bash
BIN=build/src_mpcd_base_cuda_topo_0348a \
ALPHAS="320 640 1000" \
U0S="1.0 1.5" \
AOAS="-14 -8 0 8 14" \
NX=600 NY=160 GAMMA=10 KBT=0.01 DT=0.0005 \
STEPS=2000 \
bash scripts/run_topo_darcy_naca_alpha_u0_sweep_0355.sh
```

The combined output is:

```text
runs/topo_darcy_naca_alpha_u0_sweep_0355/naca_alpha_u0_sweep_0355_combined.csv
```

## MATLAB analysis

```matlab
cd('/mnt/e/SRC_MPCD_DEV/SRC_GPU-TOPO')
addpath(genpath('matlab'))
T = plot_topo_naca_alpha_u0_sensitivity_0355( ...
    'runs/topo_darcy_naca_alpha_u0_sweep_0355/naca_alpha_u0_sweep_0355_combined.csv', ...
    'OutputDir', 'runs/topo_matlab_plots_0355', ...
    'ShowFigures', true);
```

Plots include:

- normalised drag vs AoA;
- normalised lift vs AoA;
- finesse proxy vs AoA;
- Darcy power vs AoA;
- lift-vs-drag proxy.
