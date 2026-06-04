# Virial response to a prescribed low-k density wave

This validation case is designed to make the virial pressure kick dynamically
visible without using a moving piston.

## Geometry

The setup is a fixed 2-D channel:

- `x`: periodic
- `y`: fixed `solid_thermal` walls
- no immersed solid
- no body force
- no active-domain motion

The initial particle state contains a deterministic low-wavenumber density
modulation in `x`:

```text
Ncell(x) ~= gamma * [1 + epsilon*cos(2*pi*x/Lx)]
```

with default values:

```text
Nx = Ny = 32
gamma = 40
epsilon = 0.15
modeX = 1
```

This creates a genuine spatial gradient of virial pressure:

```text
grad(Pvir) = Kvirial * grad(rho)
```

Unlike the uniform piston compression, this case should produce a visible
velocity response from the virial kick.

## Generate the state

From `matlab/`:

```matlab
addpath('.')
generate_density_wave_channel_state();
```

This writes:

```text
../initial_state_density_wave_x_32x32_g40_eps0p15.smpcd
```

## Runs

From the repository root:

```bash
./build/src_mpcd_base examples/params_density_wave_channel_q9_filtered.kv
./build/src_mpcd_base examples/params_density_wave_channel_q9_virial_K0p500_beta0p20.kv
./build/src_mpcd_base examples/params_density_wave_channel_q9_virial_K1p000_beta0p50.kv
```

The three runs compare:

1. Q9 filtered, no virial kick;
2. moderate virial kick: `Kvirial=0.50`, `virialBeta=0.20`;
3. stronger virial kick: `Kvirial=1.00`, `virialBeta=0.50`.

## Post-processing

From `matlab/`:

```matlab
addpath('.')
out = validate_density_wave_virial_channel('makePlots', true);
```

Key diagnostics:

- `densityCosModeAbsRatio`: decay of the imposed density mode;
- `uxSinModeEnd`: velocity response driven by the pressure gradient;
- `filteredStdRatio`: decay of the reconstructed low-k density content;
- `virialDuAppliedRmsEnd` and `virialDuAppliedMaxEnd`: applied virial kick;
- `kBTEnd`, `maxParticleAbsVxEnd`, `maxParticleAbsVyEnd`: stability checks.

This is an intentionally nonuniform-density test. It is complementary to the
piston EOS tests, where the virial pressure is very visible in the mean but its
spatial gradient can remain weak.
