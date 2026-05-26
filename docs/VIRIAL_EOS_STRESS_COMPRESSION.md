# Virial EOS stress-compression piston test

This validation extends the mild moving-piston EOS sweep with a deliberately
more demanding compression.  It is meant to make the virial kick dynamically
visible while keeping the method close to the validated MATLAB workflow:

- Q6 velocity projection;
- filtered Q9 low-k mass-flux projection;
- optional virial EOS pressure kick;
- final cell-relative thermostat;
- exact global momentum correction.

No limiter is added in this test.  Stability is assessed from the diagnostics.

## Geometry and compression

The numerical box remains fixed, but the active fluid domain contracts:

```text
fluidYTop0 = 0.95
fluidYTopVelocity = -0.002
nSteps = 75000
dt = 0.001
```

Therefore the active height changes from `0.95` to `0.80`, giving the expected
mean density ratio:

```text
rhoEnd/rhoStart = 0.95/0.80 = 1.1875
```

This is intentionally stronger than the standard piston validation, where the
height changes only from `0.95` to `0.90`.

## Added parameter files

```text
examples/params_piston_y_q9_filtered_stress_y080_solid_thermal_isothermal.kv
examples/params_piston_y_q9_virial_stress_y080_K0p250_beta0p10_solid_thermal_isothermal.kv
examples/params_piston_y_q9_virial_stress_y080_K0p500_beta0p20_solid_thermal_isothermal.kv
```

The first file is the filtered-Q9 baseline without virial kick.  The two virial
runs increase both `Kvirial` and `virialBeta` compared with the mild sweep.

The stronger case uses:

```text
Kvirial = 0.50
virialBeta = 0.20
```

It is intended to make the kick visible through:

```text
virialDuAppliedRms
virialDuAppliedMaxAbs
virialDuOverThermalRms
```

while checking that:

```text
kBT remains stable
mass is conserved
yWallReflectionMaxPerParticle remains small
maxParticleAbsVy stays in a safe range
```

## Run sequence

Generate the usual active-domain piston initial state from `matlab/` if needed:

```matlab
addpath('.')
generate_piston_active_y095_state();
```

Run from the repository root:

```bash
./build/src_mpcd_base examples/params_piston_y_q9_filtered_stress_y080_solid_thermal_isothermal.kv
./build/src_mpcd_base examples/params_piston_y_q9_virial_stress_y080_K0p250_beta0p10_solid_thermal_isothermal.kv
./build/src_mpcd_base examples/params_piston_y_q9_virial_stress_y080_K0p500_beta0p20_solid_thermal_isothermal.kv
```

Post-process from `matlab/`:

```matlab
addpath('.')
out = validate_piston_q9_virial_stress_compression('makePlots', true);
```

## Interpretation

This test should not be used as a production EOS calibration.  Its purpose is
to determine whether a stronger compression and stronger virial coefficients
remain numerically stable and whether the virial kick becomes visible without
requiring an additional limiter.

