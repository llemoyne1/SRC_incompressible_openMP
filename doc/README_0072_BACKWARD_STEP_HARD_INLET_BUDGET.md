# 0072 — Backward-step hard-inlet budget test, 48x24, 80000 steps

This patch adds a reduced-grid backward-step run intended to determine whether the current hard-cell-density inlet and passive outlet can relax toward a constant mass throughput when the obstacle is present.

No C++ source file is modified by this patch.

## Purpose

The 0071 straight-channel run showed that the hard inlet and passive outlet can approach an inlet/outlet flux balance without an obstacle. The 0072 run keeps the same physical channel size and the same inlet/outlet logic, but re-enables the backward-step obstacle.

The default run is the complete liquid closure chain only:

```text
Q6 velocity projection enabled through the method
Q9 mass-flux projection enabled
virial kick enabled
```

Optional Q6, Q9-only and classic cases remain available through environment flags.

## Default configuration

```text
Lx = 2.0
Ly = 1.0
Nx = 48
Ny = 24
gamma = 20
kBT = 0.0025
dt = 0.001
Uin = 0.05
CASE_STEPS = 80000
```

This corresponds to

```text
Tadv = Lx / Uin = 40
Tfinal = 80 = 2 Tadv
```

The obstacle is kept at the same physical dimensions as the previous backward-step diagnostic:

```text
x in [0.25, 0.65]
y in [0.0, 0.50]
```

## Q9 solid-mask thickness

At 48x24, the default Q9 immersed-solid halo is reduced to the smallest conservative non-zero value:

```text
q9ImmersedSolidHaloCells = 1
```

This is deliberately thinner than the previous 96x48 diagnostic halo. It leaves Q9 active over most of the fluid domain while retaining one safety layer around the obstacle. A later stress test can use `Q9_IMMERSED_HALO_CELLS=0`, but this is not recommended as the first long obstacle run.

The open-boundary exclusion is scaled to:

```text
q9OpenBoundaryExclusionCells = 3
virialOpenBoundaryExclusionCells = 3
inletReservoirCells = 3
```

## Initial state

The added MATLAB helper

```text
matlab/generate_backward_step_exact_fluid_state_0072.m
```

generates an exact-per-fluid-cell initial state: exactly `gamma` particles in every non-solid cell, no particles in obstacle cells, and a mean initial velocity `Ux = Uin`.

This is preferable for this budget test because the hard inlet targets `N = gamma` in fluid cells.

## Manual initial-state generation

If MATLAB is not available as a command-line executable, generate the state once from the MATLAB UI:

```matlab
cd('/path/to/SRC_incompressible_openMP/matlab')

generate_backward_step_exact_fluid_state_0072( ...
    'output','../initial_state_backward_step_exact_fluid_48x24_g20_kbt0p0025_ux0p05.smpcd', ...
    'Lx',2.0, ...
    'Ly',1.0, ...
    'Nx',48, ...
    'Ny',24, ...
    'gamma',20, ...
    'kBT',0.0025, ...
    'Ux',0.05, ...
    'Uy',0.0, ...
    'xMin',0.25, ...
    'xMax',0.65, ...
    'yMin',0.0, ...
    'yMax',0.50);

cd('..')
```

Expected order of magnitude:

```text
solid cells ≈ 120
fluid cells ≈ 1032
particles ≈ 20640
```

## Smoke run

```bash
RUN_ROOT=runs/backward_step_hard_inlet_budget_0072_smoke \
CASE_STEPS=1000 \
SUMMARY_EVERY=100 \
DUMP_STATE_EVERY=500 \
NUM_THREADS=8 \
AUTO_ANALYZE=0 \
./scripts/run_backward_step_hard_inlet_budget_0072.sh
```

## Main 80000-step run

```bash
RUN_ROOT=runs/backward_step_hard_inlet_budget_0072 \
RUN_Q6=0 \
RUN_Q9=0 \
RUN_Q9_VIRIAL=1 \
RUN_CLASSIC=0 \
CASE_STEPS=80000 \
SUMMARY_EVERY=250 \
DUMP_STATE_EVERY=5000 \
NUM_THREADS=8 \
AUTO_ANALYZE=0 \
./scripts/run_backward_step_hard_inlet_budget_0072.sh
```

## Optional comparison cases

The script defaults to Q9+virial only. To also run Q6 and Q9-only:

```bash
RUN_Q6=1 RUN_Q9=1 RUN_Q9_VIRIAL=1 ./scripts/run_backward_step_hard_inlet_budget_0072.sh
```

To stress-test a zero Q9 halo later:

```bash
Q9_IMMERSED_HALO_CELLS=0 RUN_ROOT=runs/backward_step_hard_inlet_budget_0072_halo0 ./scripts/run_backward_step_hard_inlet_budget_0072.sh
```

Do not use halo 0 as the first long validation run.

## MATLAB analysis

From MATLAB:

```matlab
cd('/path/to/SRC_incompressible_openMP/matlab')

R = analyze_backward_step_hard_inlet_budget_0072( ...
    'root','..', ...
    'runRoot','runs/backward_step_hard_inlet_budget_0072', ...
    'lateFraction',0.50);

V = make_backward_step_hard_inlet_visual_report_0072( ...
    'root','..', ...
    'runRoot','runs/backward_step_hard_inlet_budget_0072', ...
    'maxFramesPerCase',12);

cd('..')
```

Main outputs:

```text
runs/backward_step_hard_inlet_budget_0072/analysis_0072/mass_budget_summary_0072.csv
runs/backward_step_hard_inlet_budget_0072/analysis_0072/mass_budget_timeseries_all_cases.csv
runs/backward_step_hard_inlet_budget_0072/visual_report_0072/
```

## Primary interpretation criteria

The run is intended to answer whether the obstacle creates a persistent retention regime or whether the system eventually approaches a constant-throughput state.

Focus on late-window quantities:

```text
totalFluidMassSlopeLate
upstreamLowerMassSlopeLate
frontBandMassSlopeLate
downstreamLowerMassSlopeLate
outletOverInletFluxProxyMeanLate
stdFluidNMeanLate
maxFluidNMeanLate
```

A favorable outcome is:

```text
totalFluidMassSlopeLate -> 0
outletOverInletFluxProxyMeanLate -> 1
stdFluidN and maxFluidN bounded
```

A persistent obstacle-induced retention problem is indicated by:

```text
totalFluidMassSlopeLate > 0
upstreamLowerMassSlopeLate > 0
frontBandMassSlopeLate > 0
outletOverInletFluxProxyMeanLate < 1
```

