# First Poiseuille validation workflow

This branch keeps the C++ solver as a compact SRC/MPCD dynamics engine. The
Poiseuille validation is therefore performed from primitive `.smpcd` dumps and
`summary_runtime.csv` using MATLAB.

## Run the three first channel cases

Generate or place an initial state at the path specified by `inputState`, usually
`initial_state.smpcd` at the repository root. Then run:

```bash
./build/src_mpcd_base examples/params_poiseuille_y_specular.kv
./build/src_mpcd_base examples/params_poiseuille_y_bounceback.kv
./build/src_mpcd_base examples/params_poiseuille_y_bounceback_vp.kv
```

The three cases use a periodic `x` direction, walls in `y`, and a weak uniform
body acceleration in `x`.

The examples are intentionally moderate (`Nx=Ny=32`, `nSteps=10000`, dumps every
250 steps). Increase `nSteps` and/or decrease `dumpStateEvery` only when a longer
average is needed.

## Inspect runtime control diagnostics

```matlab
addpath('matlab')
plot_smpcd_summary('runs/poiseuille_y_bounceback_vp');
```

Check at least:

- real mass and particle count remain constant;
- `kBT` does not drift excessively for the selected forcing and duration;
- wall hit counters are non-zero on the expected faces;
- virtual particle diagnostics are non-zero only for VP cases.

## Average and fit one velocity profile

```matlab
out = analyze_poiseuille_profile('runs/poiseuille_y_bounceback_vp', ...
    'flowComponent', 'Ux', ...
    'profileDirection', 'y', ...
    'fitStartFraction', 0.5, ...
    'excludeWallCells', 2);
```

The script computes the time-averaged profile `Ux(y)`, fits

```text
U(y) = c0 + c1 y + c2 y^2
```

and estimates

```text
nu_eff = -bodyAccelerationX / (2 c2)
```

when `bodyAccelerationX` and the quadratic curvature are available.

For this first validation, `nu_eff` should be treated as a qualitative indicator,
not as a final calibrated transport coefficient. The run length is short and no
mass-aware thermostat is active yet.

## Compare specular, bounceback and bounceback+VP

```matlab
cmp = compare_poiseuille_runs({ ...
    'runs/poiseuille_y_specular', ...
    'runs/poiseuille_y_bounceback', ...
    'runs/poiseuille_y_bounceback_vp'}, ...
    'labels', {'specular', 'bounceback', 'bounceback+VP'}, ...
    'flowComponent', 'Ux', ...
    'profileDirection', 'y', ...
    'fitStartFraction', 0.5, ...
    'excludeWallCells', 2);
```

Expected qualitative behavior:

- `specular` gives a slip-wall reference and should not be interpreted as no-slip;
- `bounceback` should reduce slip but remains a crude wall model;
- `bounceback+VP` should improve wall coupling and is the reference path for
  later Poiseuille and cylinder validation.

## Output objects

`analyze_poiseuille_profile` returns a struct containing:

- `profileTable`: coordinate, time-averaged velocity, temporal standard deviation, fit;
- `fit`: quadratic coefficients, `R2`, RMS residual, `nuEff`;
- `profiles`: all selected instantaneous profiles;
- `summaryTable` and `frameTable` for traceability.
