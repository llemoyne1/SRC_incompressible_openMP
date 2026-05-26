# Q6 channel Poiseuille validation

This note documents the first use of the Q6 adapter with the generic elliptic
projection core in a periodic-x / wall-y channel.

The code path remains deliberately compact. The Q6 adapter infers the elliptic
boundary policy from the particle boundary modes:

- periodic particle direction -> periodic elliptic direction;
- non-periodic wall direction -> no-normal-flux elliptic direction.

The first documented channel validation is therefore:

```text
bcLeft   = periodic
bcRight  = periodic
bcBottom = solid
bcTop    = solid
```

with a body acceleration in `+x`.

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

## Run the C++ examples

Run from the repository root:

```bash
./build/src_mpcd_base examples/params_poiseuille_y_classic_solid_thermal_short.kv
./build/src_mpcd_base examples/params_poiseuille_y_q6_solid_thermal_short.kv
```

## Analyze

Run from the `matlab/` directory:

```matlab
addpath('.')
out = validate_poiseuille_q6_channel_short('makePlots', true);
```

The most important diagnostics are:

- `q6RuntimeDivAfterEnd`, which should be near the requested CG tolerance;
- `q6RuntimeResidualEnd`, the final relative CG residual;
- `fitR2` and `nuEff`, which indicate whether the mean profile remains
  Poiseuille-like;
- `kBTEnd`, to ensure the thermostat remains stable.

This is a short smoke/validation case, not a final viscosity calibration. Longer
runs remain necessary for accurate transport measurements.
