# Long Poiseuille validation for Q6 channel projection

This protocol documents the first long periodic-x / wall-y Poiseuille comparison
between the compressible SRC/MPCD baseline and the Q6 channel projection.

It does not change the solver. It only adds reproducible parameter files and a
MATLAB wrapper around the existing short-channel validator.

## Scope

The intended configuration is:

```text
bcLeft   = periodic
bcRight  = periodic
bcBottom = solid
bcTop    = solid
method   = classic or q6
```

For Q6, the adapter uses the generic elliptic projection core with:

```text
projectionOperator = channel_fv_cg
```

The elliptic boundary interpretation is:

```text
x direction : periodic
y direction : no-normal-flux wall
```

## Generate the initial state

Run from the `matlab/` directory:

```matlab
addpath('.')
generate_poiseuille_q6_channel_short_state();
```

This writes:

```text
../initial_state_poiseuille_32x32_g40_kbt0p01.smpcd
```

The long runs reuse the same initial state as the short smoke test so that the
comparison isolates run duration rather than a new initialization.

## Run the long C++ cases

Run from the repository root:

```bash
./build/src_mpcd_base examples/params_poiseuille_y_classic_solid_thermal_long.kv
./build/src_mpcd_base examples/params_poiseuille_y_q6_solid_thermal_long.kv
```

The default long cases use:

```text
Nx = Ny = 32
gamma = 40
dt = 0.001
nSteps = 50000
tEnd = 50
bodyAccelerationX = 0.005
summaryEvery = 500
dumpStateEvery = 1000
```

## Analyze

Run from the `matlab/` directory:

```matlab
addpath('.')
out = validate_poiseuille_q6_channel_long('makePlots', true);
```

Default analysis paths are relative to `matlab/`:

```text
../runs/poiseuille_y_classic_solid_thermal_long
../runs/poiseuille_y_q6_solid_thermal_long
```

The default fit window is the second half of the saved trajectory:

```text
fitStartFraction = 0.5
excludeWallCells = 3
```

## Expected diagnostics

The important quantities are:

```text
fitR2
nuEff
uCenter
uMax
kBTEnd
q6RuntimeDivAfterEnd
q6RuntimeResidualEnd
q6IterationsEnd
```

A representative validation showed:

```text
classic : fitR2 ≈ 0.77, nuEff ≈ 0.117, kBT ≈ 0.0100
q6      : fitR2 ≈ 0.82, nuEff ≈ 0.118, kBT ≈ 0.0099
```

with Q6 runtime divergence after projection near `1e-10`.

The key interpretation is that Q6 improves the parabolic quality of the mean
profile while preserving a viscosity estimate close to the compressible baseline
for this configuration.
