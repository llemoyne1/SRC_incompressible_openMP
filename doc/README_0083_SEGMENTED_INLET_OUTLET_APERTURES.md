# 0083 — Segmented inlet/outlet apertures with wall corners

## Purpose

This patch finalizes a first implementation of segmented open boundaries for the `feature/inlet-outlet` branch.  The motivation is the outlet-corner diagnosis from `0082`: in a channel with solid top/bottom walls, a fully open right boundary can create an organized pre-outlet recirculation near the wall/outlet corners.  The new aperture mechanism lets only a central portion of an inlet/outlet face exchange particles and flux; the complementary boundary portions behave as impermeable particle walls.

The patch is still scoped to **domain boundary inlet/outlet**.  It does not reintroduce immersed-solid validation.

## New parameters

```text
openBoundaryApertureEnable = false
leftOpenYMin = 0.0
leftOpenYMax = -1.0
rightOpenYMin = 0.0
rightOpenYMax = -1.0
bottomOpenXMin = 0.0
bottomOpenXMax = -1.0
topOpenXMin = 0.0
topOpenXMax = -1.0
```

Negative high bounds inherit the corresponding active-domain maximum.  With `openBoundaryApertureEnable=false`, the historical full-face inlet/outlet behavior is preserved.

For a left/right channel, the useful parameters are:

```text
leftOpenYMin, leftOpenYMax
rightOpenYMin, rightOpenYMax
```

For `Ly=1`, `Ny=24`, the script `0083` defaults to:

```text
leftOpenYMin  = 0.08333333333333333
leftOpenYMax  = 0.9166666666666666
rightOpenYMin = 0.08333333333333333
rightOpenYMax = 0.9166666666666666
```

This closes two cell rows next to the bottom and top walls at both the inlet and outlet.

## Implemented coupling levels

The aperture is applied coherently to:

1. **Particle boundary conditions**
   - hard-cell-density inlet reservoir cells are built only inside the inlet aperture;
   - particles crossing an outlet face are deleted only inside the outlet aperture;
   - particles crossing the closed portions of an inlet/outlet face are reflected as solid-wall particles.

2. **Q6 open-boundary projection**
   - the generic elliptic projection BC now supports per-boundary flux profiles;
   - open velocity flux is prescribed only on aperture rows/columns;
   - closed portions have zero normal flux.

3. **Q9 open-boundary projection**
   - Q9 uses the same segmented mass-flux profiles;
   - Q9 open-boundary exclusion cells are restricted to the open aperture portions, not to the full boundary height.

4. **Virial open-boundary exclusion**
   - virial open-boundary exclusion is also restricted to the open aperture portions.

## Run script

```bash
scripts/run_poiseuille_segmented_inlet_outlet_softlimited_q9_0083.sh
```

Defaults:

```text
Lx = 2.0
Ly = 1.0
Nx = 48
Ny = 24
gamma = 20
kBT = 0.0025
Uin = 0.05
CASE_STEPS = 60000
INLET_RAMP_END_TIME = 20.0
Q9_CORRECTION_LIMITER_MODE = thermal_soft
Q9_CORRECTION_LIMITER_OVER_THERMAL = 0.5
RUN_Q9_VIRIAL = 1
```

## Smoke run

Generate the initial state manually from MATLAB if needed:

```matlab
cd('/home/llemoyne/GitHub/SRC_incompressible_openMP-elliptic-q6/matlab')

generate_open_channel_classic_state( ...
    'output','../initial_state_poiseuille_hard_inlet_48x24_g30_kbt0p0025_ux0p0.smpcd', ...
    'Lx',2.0, ...
    'Ly',1.0, ...
    'Nx',48, ...
    'Ny',24, ...
    'gamma',30, ...
    'kBT',0.0025, ...
    'inletUx',0.0);

cd('..')
```

Then:

```bash
RUN_ROOT=runs/poiseuille_segmented_io_0083_g30_smoke \
GAMMA=30 \
CASE_STEPS=2000 \
SUMMARY_EVERY=25 \
DUMP_STATE_EVERY=1000 \
INLET_RAMP_END_TIME=1.0 \
NUM_THREADS=8 \
AUTO_ANALYZE=0 \
./scripts/run_poiseuille_segmented_inlet_outlet_softlimited_q9_0083.sh
```

Expected quick checks in `summary_runtime.csv`:

```text
inletReservoirCells = 60        # for 48x24, 3 inlet columns, 20 open rows
q9OpenBoundaryExcludedCells = 120
virialOpenBoundaryExcludedCells = 120
q9CorrectionVelocityLimiter = 0.025
```

For `gamma=30`, the gamma-relative Q9 thresholds should remain:

```text
q9MinCellMassForCorrection = 12
q9MassFloorForCorrection = 12
q9LowMassRampStart = 1.5
q9LowMassRampEnd = 12
```

## Long run

```bash
RUN_ROOT=runs/poiseuille_segmented_io_0083_g30 \
GAMMA=30 \
CASE_STEPS=80000 \
SUMMARY_EVERY=100 \
DUMP_STATE_EVERY=5000 \
INLET_RAMP_END_TIME=40.0 \
NUM_THREADS=8 \
AUTO_ANALYZE=0 \
./scripts/run_poiseuille_segmented_inlet_outlet_softlimited_q9_0083.sh
```

The longer ramp is recommended because the previous full-face run still showed a mass deficit and strong late outlet oscillations.

## Analysis

The standard Poiseuille analysis remains:

```matlab
cd matlab
R = analyze_poiseuille_hard_inlet_free_outlet_0077( ...
    'root','..', ...
    'runRoot','runs/poiseuille_segmented_io_0083_g30', ...
    'lateFraction',0.50);
```

The outlet-corner diagnostic from `0082` should be rerun on the same directory:

```matlab
C = analyze_poiseuille_outlet_corner_bands_0082( ...
    'root','..', ...
    'runRoot','runs/poiseuille_segmented_io_0083_g30', ...
    'wallBandCells',3, ...
    'frameStride',1, ...
    'makePlots',true, ...
    'showFigures',true, ...
    'closeFigures',false);
```

A successful outcome would show reduced pre-outlet negative-flux fractions in the top/bottom bands and improved stabilization of total mass and profile quality.
