# Long Poiseuille validation for filtered Q9 in a channel

This protocol compares three long periodic-x / solid-y Poiseuille runs:

- `classic`: compressible SRC/MPCD baseline,
- `q6`: velocity projection with the generic elliptic channel operator,
- `q9`: Q6 followed by filtered mass-flux projection.

The Q9 run uses the MATLAB-like elliptic low-pass target filter and does not use
a velocity-kick limiter.

## Scope

The intended configuration is:

```text
bcLeft   = periodic
bcRight  = periodic
bcBottom = solid
bcTop    = solid
method   = classic, q6 or q9
```

For Q6/Q9, the elliptic interpretation is:

```text
x direction : periodic
y direction : no-normal-flux wall
```

The goal is to validate the first wall-bounded use of filtered Q9. This is not
yet a free-surface, virial/EOS, inlet/outlet or surface-tension validation.

## Initial state

Run from the `matlab/` directory:

```matlab
addpath('.')
generate_poiseuille_q6_channel_short_state();
```

This writes:

```text
../initial_state_poiseuille_32x32_g40_kbt0p01.smpcd
```

## Runs

Run from the repository root:

```bash
./build/src_mpcd_base examples/params_poiseuille_y_classic_solid_thermal_long.kv
./build/src_mpcd_base examples/params_poiseuille_y_q6_solid_thermal_long.kv
./build/src_mpcd_base examples/params_poiseuille_y_q9_filtered_solid_thermal_long.kv
```

The Q9 parameters are intentionally close to the MATLAB reference strategy:

```text
q9DensityRelaxationBeta = 0.0005
q9TargetFilter = elliptic_lowpass
q9LowKMaxIndex = 2
q9EllipticLowPassPasses = 1
```

## Analysis

Run from the `matlab/` directory:

```matlab
addpath('.')
out = validate_poiseuille_q9_channel_long('makePlots', true);
```

Default paths are relative to `matlab/`:

```text
../runs/poiseuille_y_classic_solid_thermal_long
../runs/poiseuille_y_q6_solid_thermal_long
../runs/poiseuille_y_q9_filtered_solid_thermal_long
```

The analysis reports:

- Poiseuille fit diagnostics (`fitR2`, `nuEff`, `uCenter`, `uMax`),
- runtime Q6 diagnostics,
- runtime Q9 residual, target-filter ratio and correction-velocity diagnostics,
- raw occupancy fluctuations `std(N)`,
- elliptic-lowpass occupancy fluctuations, using the same channel-style
  no-normal-flux interpretation in `y`.

## Why filtered density diagnostics are needed

Filtered Q9 is designed to act on coherent low-frequency density modes, not on
cell-by-cell occupancy noise. Therefore raw `std(N)` alone can be misleading.
The validator also computes an elliptic-lowpass diagnostic of `N - mean(N)` with
`lowKMaxIndex = 2`, mirroring the Q9 target filter. This diagnostic is closer to
the part of the density field that Q9 is intended to control.

## Expected behavior

A healthy first Q9 channel validation should show:

- Q9 residual near the elliptic tolerance,
- small Q9 correction velocities,
- stable `kBT`,
- a Poiseuille profile comparable to Q6,
- no catastrophic growth of raw or filtered density fluctuations,
- filtered density diagnostics that are at least not worse than Q6 over the
  stationary tail window.
