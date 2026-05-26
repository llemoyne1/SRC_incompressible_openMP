# Solid thermal wall: transposed Poiseuille validation

This validation checks that the generic `solid` / thermal wall boundary is not hard-coded to the y-direction.

Two statistically equivalent Poiseuille cases are used:

1. **Y-wall channel**
   - `bcLeft = periodic`, `bcRight = periodic`
   - `bcBottom = solid`, `bcTop = solid`
   - `bodyAccelerationX > 0`
   - validation profile: `Ux(y)`

2. **X-wall channel**
   - `bcLeft = solid`, `bcRight = solid`
   - `bcBottom = periodic`, `bcTop = periodic`
   - `bodyAccelerationY > 0`
   - validation profile: `Uy(x)`

The two profiles should agree up to statistical noise and finite sampling.

## Long validation runs

Generate or copy `initial_state.smpcd` to the repository root, then run:

```bash
./build/src_mpcd_base examples/params_poiseuille_y_solid_thermal_long.kv
./build/src_mpcd_base examples/params_poiseuille_x_solid_thermal_long.kv
```

The default files use:

```text
nSteps = 50000
dumpStateEvery = 1000
summaryEvery = 100
numThreads = 4
```

They are intended to give a more meaningful wall-boundary validation than the short smoke cases.

## MATLAB analysis

```matlab
addpath('matlab')

out = validate_solid_thermal_poiseuille_symmetry( ...
    'runs/poiseuille_y_solid_thermal_long', ...
    'runs/poiseuille_x_solid_thermal_long', ...
    'fitStartFraction', 0.5, ...
    'excludeWallCells', 2, ...
    'stationaryWindowFraction', 0.25);
```

The analysis reports:

- profile-mean `nuEff` for both orientations;
- profile-mean `R²`;
- center-minus-wall velocity;
- wall asymmetry;
- thermal control diagnostics;
- normalized RMS and maximum profile differences between `Ux(y)` and `Uy(x)`.

For calibration, prefer the fit of the time-averaged profile over the average of instantaneous `nuEff(t)`, which is much noisier in SRC/MPCD.
