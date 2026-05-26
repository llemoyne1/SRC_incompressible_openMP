# 0069 — Backward-step mass-budget diagnostics + systematic visual reports

This diagnostic package is for the hard-inlet backward-step case after Q9 low-mass `ramp_floor` regularization.

It does **not** modify the C++ solver. It adds a new run script and two MATLAB post-processing scripts.

## Goals

1. Reduce the Q9 immersed-solid halo immediately in the next run:

```text
q9ImmersedSolidHaloCells = 3
```

instead of the previous long-run value of 5.

2. Use frequent dumps by default:

```text
DUMP_STATE_EVERY = 1000
```

so that the evolution of `N`, Q6/Q9 masks, and accumulation zones is visible.

3. Quantify mass by zones:

- inlet band
- outlet band
- front band immediately upstream of the obstacle
- upstream lower pocket
- upstream upper region
- above-obstacle region
- downstream lower wake
- downstream upper region
- Q9 open-excluded cells
- Q9 immersed-halo cells
- Q9 geometrically active cells

4. Generate systematic PNG visual reports per case and frame.

## Run

From the repository root:

```bash
chmod +x scripts/run_backward_step_mass_budget_viz_0069.sh

CASE_STEPS=8000 \
SUMMARY_EVERY=250 \
DUMP_STATE_EVERY=1000 \
NUM_THREADS=8 \
./scripts/run_backward_step_mass_budget_viz_0069.sh
```

The script launches exactly three cases:

```text
backstep_q6_hard_inlet_halo3_diag
backstep_q9_hard_inlet_s003_halo3_diag
backstep_q9_virial_hard_inlet_s003_halo3_diag
```

The default output directory is:

```text
runs/backward_step_mass_budget_viz_0069
```

## Analyze mass budget

```matlab
cd matlab
R = analyze_backward_step_mass_budget_0069( ...
    'root','..', ...
    'runRoot','runs/backward_step_mass_budget_viz_0069');
cd ..
```

Outputs:

```text
runs/backward_step_mass_budget_viz_0069/analysis_0069/mass_budget_timeseries_all_cases.csv
runs/backward_step_mass_budget_viz_0069/analysis_0069/mass_budget_summary_0069.csv
runs/backward_step_mass_budget_viz_0069/analysis_0069/plot_*.png
```

## Generate visual report

```matlab
cd matlab
V = make_backward_step_visual_report_0069( ...
    'root','..', ...
    'runRoot','runs/backward_step_mass_budget_viz_0069');
cd ..
```

Outputs:

```text
runs/backward_step_mass_budget_viz_0069/visual_report_0069/<case>/frame_*.png
```

Each panel contains, by default:

```text
N, Ux, Uy, omega, q9Active, q9ImmersedHalo, q9LowMassRamp
```

## Notes

The flux quantities written by `analyze_backward_step_mass_budget_0069` are diagnostic proxies based on cell-centered sums of `N*U`. They are not exact finite-volume face fluxes. They are intended to identify where mass accumulates and whether the outlet transport is insufficient relative to hard-inlet feeding.
