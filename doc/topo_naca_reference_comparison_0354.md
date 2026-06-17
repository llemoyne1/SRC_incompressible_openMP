# 0354-topo: normalized comparison to NACA 0012 reference polar

This patch adds a MATLAB postprocessor for qualitative comparison between the
SRC-Darcy NACA proxy sweep and a reference NACA 0012 polar.

The comparison is normalized.  It does not treat Darcy/Brinkman proxy forces as
calibrated aerodynamic coefficients.

## Reference data

The included CSV is a compact reference table derived from published
NASA/Ladson NACA 0012 validation values summarized for `Re=6e6`, `Ma=0.15`.

```text
data/reference/naca0012_ladson_re6e6_reference_0354.csv
```

Columns:

```text
aoaDeg, CL, CD, source, reynolds, mach
```

Negative-angle values are mirrored from the symmetric NACA 0012 behavior for
qualitative comparison.

## MATLAB use

```matlab
cd('/mnt/e/SRC_MPCD_DEV/SRC_GPU-TOPO')
addpath(genpath('matlab'))

C = plot_topo_naca_reference_comparison_0354( ...
    'runs/topo_darcy_naca_re_sweep_0353/naca_re_polar_proxy_0353.csv', ...
    'ReferenceCsv', 'data/reference/naca0012_ladson_re6e6_reference_0354.csv', ...
    'OutputDir', 'runs/topo_matlab_plots_0354', ...
    'ShowFigures', true);
```

or run:

```matlab
run('matlab/topo/run_topo_naca_reference_comparison_0354.m')
```

## Outputs

```text
runs/topo_matlab_plots_0354/naca0012_reference_comparison_0354_comparison.csv
runs/topo_matlab_plots_0354/naca0012_reference_comparison_0354_lift_norm.png/pdf
runs/topo_matlab_plots_0354/naca0012_reference_comparison_0354_drag_norm.png/pdf
runs/topo_matlab_plots_0354/naca0012_reference_comparison_0354_lift_vs_drag_norm.png/pdf
runs/topo_matlab_plots_0354/naca0012_reference_comparison_0354_finesse_norm.png/pdf
```
