# 0088 — Full inlet/outlet with VP/no-slip walls and Poiseuille boundary profile

## Purpose

Patch 0088 is the next step after the clean 0087 baseline:

- full-height hard inlet on the left;
- full-height free outlet on the right;
- `q9OpenBoundaryExclusionCells = 0`;
- `virialOpenBoundaryExclusionCells = 0`;
- thermal soft Q9 limiter;
- no immersed solid.

The 0087 run showed that the inlet/outlet core is clean when Q9/virial act up to the open faces.  Patch 0088 reintroduces top/bottom solid thermal walls, but avoids the incompatible uniform-inlet/no-slip combination by prescribing a Poiseuille-shaped x-velocity profile at the inlet and in the Q6/Q9 open-boundary fluxes.

## New parameter

The patch adds:

```text
inletVelocitySpatialProfile = uniform | poiseuille_y | poiseuille_y_mean | poiseuille_y_max
```

The default is `uniform`, so historical runs are unchanged.

For x-face inlet/outlet pairs, `poiseuille_y` and `poiseuille_y_mean` use the stored `inletUx*` value as the cross-section mean velocity:

```text
u_x(y) = 6 U_mean eta (1 - eta), eta = (y - y_min)/(y_max - y_min)
```

`poiseuille_y_max` instead uses `inletUx*` as the centerline velocity:

```text
u_x(y) = 4 U_max eta (1 - eta)
```

In 0088, `UIN=0.05` is therefore interpreted as the mean velocity, with a centerline velocity of approximately `0.075`.

The profile is applied consistently to:

1. hard-cell inlet particle velocities;
2. Q6 open-boundary velocity flux profile;
3. Q9 open-boundary mass-flux profile.

## Runner

```text
scripts/run_open_channel_full_io_vp_poiseuille_q9_virial_excl0_0088.sh
```

Default case:

```text
method = q9_virial
bcLeft = inlet
bcRight = outlet
bcBottom = solid
bcTop = solid
wallAccommodation = 1.0
inletVelocitySpatialProfile = poiseuille_y_mean
q9OpenBoundaryExclusionCells = 0
virialOpenBoundaryExclusionCells = 0
q9CorrectionLimiterMode = thermal_soft
q9CorrectionVelocityLimiterOverThermal = 0.5
```

## Generate initial state

MATLAB is usually not available from bash on the target machine, so generate the state manually:

```matlab
cd('/home/llemoyne/GitHub/SRC_incompressible_openMP-elliptic-q6/matlab')

generate_open_channel_classic_state( ...
    'output','../initial_state_open_channel_full_io_vp_poiseuille_48x24_g30_kbt0p0025_ux0p0.smpcd', ...
    'Lx',2.0, ...
    'Ly',1.0, ...
    'Nx',48, ...
    'Ny',24, ...
    'gamma',30, ...
    'kBT',0.0025, ...
    'inletUx',0.0);

cd('..')
```

## Smoke

```bash
RUN_ROOT=runs/open_channel_full_io_vp_poiseuille_0088_g30_smoke \
GAMMA=30 \
CASE_STEPS=2000 \
SUMMARY_EVERY=25 \
DUMP_STATE_EVERY=1000 \
INLET_RAMP_END_TIME=1.0 \
NUM_THREADS=8 \
AUTO_ANALYZE=0 \
./scripts/run_open_channel_full_io_vp_poiseuille_q9_virial_excl0_0088.sh
```

Expected checks in `summary_runtime.csv`:

```text
bcBottom/bcTop are solid in params_used.kv
inletVelocitySpatialProfile = poiseuille_y_mean
q9OpenBoundaryExcludedCells = 0
virialOpenBoundaryExcludedCells = 0
q9CorrectionVelocityLimiter ≈ 0.025
inletReservoirCells = 72 for 48x24 full-height inlet with 3 reservoir columns
```

## Long run

```bash
RUN_ROOT=runs/open_channel_full_io_vp_poiseuille_0088_g30 \
GAMMA=30 \
CASE_STEPS=80000 \
SUMMARY_EVERY=100 \
DUMP_STATE_EVERY=5000 \
INLET_RAMP_END_TIME=40.0 \
NUM_THREADS=8 \
AUTO_ANALYZE=0 \
./scripts/run_open_channel_full_io_vp_poiseuille_q9_virial_excl0_0088.sh
```

## Analysis

Use the existing analyzers:

```matlab
cd('/home/llemoyne/GitHub/SRC_incompressible_openMP-elliptic-q6/matlab')

R = analyze_poiseuille_hard_inlet_free_outlet_0077( ...
    'root','..', ...
    'runRoot','runs/open_channel_full_io_vp_poiseuille_0088_g30', ...
    'caseGlob','openchan_*', ...
    'lateFraction',0.50);

C = analyze_open_channel_full_io_q9_boundary_modes_0086( ...
    'root','..', ...
    'runRoot','runs/open_channel_full_io_vp_poiseuille_0088_g30', ...
    'caseGlob','openchan_*', ...
    'lateFraction',0.50, ...
    'makePlots',true, ...
    'showFigures',true, ...
    'closeFigures',false);

cd('..')
```

Here the Poiseuille profile fit is meaningful again, unlike the 0087 slip-wall baseline.

## Interpretation

A successful 0088 run should preserve the good 0087 mass/temperature behavior while producing a stable parabolic profile compatible with the solid top/bottom walls.  If this fails while 0087 remains clean, the remaining issue is the coupling between open boundaries and thermal wall/VP no-slip, not the hard inlet, not the outlet, and not Q9/virial in the bulk.
