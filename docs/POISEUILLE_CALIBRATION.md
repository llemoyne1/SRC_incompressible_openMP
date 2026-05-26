# Poiseuille calibration post-processing

The Poiseuille scripts are intended to become the main calibration workflow for
transport properties in the SRC/MPCD C++ code. The C++ solver only writes
primitive particle dumps and runtime control diagnostics; the velocity profiles,
fit quality, convergence checks and viscosity estimates are computed in MATLAB.

## Single-run analysis

```matlab
addpath('matlab')

out = analyze_poiseuille_profile('runs/poiseuille_y_bounceback_vp', ...
    'flowComponent', 'Ux', ...
    'profileDirection', 'y', ...
    'fitStartFraction', 0.5, ...
    'excludeWallCells', 2, ...
    'stationaryWindowFraction', 0.25, ...
    'saveTables', true, ...
    'saveMat', true);
```

The output structure contains:

- `profileTable`: time-averaged coordinate/profile/standard-deviation/fit;
- `frameMetrics`: one line per dump with instantaneous profile metrics;
- `stationarity`: tail-window statistics and drift indicators;
- `fit`: fit of the time-averaged profile;
- `summaryTable`: copy of the runtime control diagnostics.

When `saveTables=true`, the script writes:

```text
poiseuille_profile_table.csv
poiseuille_frame_metrics.csv
```

inside the run directory.

## Frame-by-frame metrics

For each dumped state, the script now computes:

```text
uCenter, uMean, uMax
wallLow, wallHigh, wallMean
centerMinusWall, wallAsymmetry
quadratic c2, R2, RMS residual
nuEff = -bodyAcceleration/(2*c2)
kBT, stdN, totalMass, Px, Py
virtualParticleCount, virtualMass
```

This makes it possible to detect whether the run is still transient before
using `nuEff` as a calibration estimate.

## Stationarity indicators

The last part of the averaging window is used as a tail window. Its size is
controlled by:

```matlab
'stationaryWindowFraction', 0.25
```

For each control metric, the script reports:

```text
meanValue
stdValue
slopePerStep
relativeDriftOverTail
firstValue
lastValue
nSamples
```

For viscosity calibration, inspect at least:

- `nuEff` tail mean and relative drift;
- `R2` tail mean;
- `kBT` relative drift;
- `centerMinusWall` and `wallAsymmetry`.

A good calibration run should have a stable `nuEff(t)`, high enough `R2`, small
thermal drift, and acceptable wall symmetry.

## Comparing boundary models

```matlab
cmp = compare_poiseuille_runs({ ...
    'runs/poiseuille_y_specular', ...
    'runs/poiseuille_y_bounceback', ...
    'runs/poiseuille_y_bounceback_vp'}, ...
    'labels', {'specular', 'bounceback', 'bounceback+VP'}, ...
    'flowComponent', 'Ux', ...
    'profileDirection', 'y', ...
    'fitStartFraction', 0.5, ...
    'excludeWallCells', 2, ...
    'stationaryWindowFraction', 0.25);
```

The comparison table includes both time-averaged profile metrics and tail-window
metrics such as `nuEffTailMean`, `nuEffTailStd`, `nuEffTailRelDrift`,
`kBTTailMean` and `kBTTailRelDrift`.

## Interpretation for the first wall tests

- `specular` is a slip-wall reference. A parabolic no-slip fit is generally not
  meaningful.
- `bounceback` should add wall friction but may retain large slip.
- `bounceback+VP` is the first useful candidate for no-slip calibration.

The effective viscosity should be used only when the profile is stationary and
sufficiently parabolic. Otherwise, use the plots to decide whether the run must
be longer, the forcing weaker, the wall model adjusted, or a thermostat added.
