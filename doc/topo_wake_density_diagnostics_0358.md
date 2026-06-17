# 0358-topo: wake density diagnostics from dumps

This patch adds MATLAB post-processing to quantify density depletion and wake
momentum deficit from `.smpcd` dumps.

Main function:

```text
matlab/topo/analyze_topo_wake_density_0358.m
```

It computes, for every dump:

- mean occupancy `N` upstream, in the near wake and in the far wake;
- `N_wake / N_upstream`;
- `rho_wake / rho_upstream`;
- `Ux_wake / Ux_upstream`;
- a simple momentum-deficit proxy `rho ux (Uref-ux)`.

The object region is inferred from `immersedSolidCx/Cy/R` or
`darcyCircleCx/Cy/R`.  For NACA/airfoil cases, pass `ObjectBox` explicitly.

## MATLAB usage

```matlab
cd('/mnt/e/SRC_MPCD_DEV/SRC_GPU-TOPO')
addpath(genpath('matlab'))

[T,S] = analyze_topo_wake_density_0358( ...
    'runs/topo_vk_0356f_darcy5000_matched', ...
    'OutputDir', 'runs/topo_vk_0356f_darcy5000_matched/analysis', ...
    'MakePlots', true, ...
    'ShowFigures', true);
```

For an airfoil-like run:

```matlab
[T,S] = analyze_topo_wake_density_0358( ...
    'runs/topo_darcy_naca_re_sweep_0353_0012_a8', ...
    'ObjectBox', [0.44 0.66 0.13 0.27], ...
    'OutputDir', 'runs/topo_darcy_naca_re_sweep_0353_0012_a8/analysis', ...
    'MakePlots', true, ...
    'ShowFigures', true);
```

## Command-line MATLAB wrapper

```bash
RUN_ROOT=runs/topo_vk_0356f_darcy5000_matched \
OUT_DIR=runs/topo_vk_0356f_darcy5000_matched/analysis \
SHOW_FIGURES=false \
bash scripts/run_matlab_topo_wake_density_0358.sh
```

## Outputs

```text
analysis/wake_density_0358.csv
analysis/wake_density_summary_0358.csv
analysis/wake_density_ratio_0358.png/pdf
analysis/wake_velocity_ratio_0358.png/pdf
analysis/wake_momentum_deficit_0358.png/pdf
```

Important columns:

```text
nearWake_N_over_upstream
farWake_N_over_upstream
nearWake_Ux_over_upstream
nearWake_momentumDeficit_mean
farWake_momentumDeficit_mean
```
