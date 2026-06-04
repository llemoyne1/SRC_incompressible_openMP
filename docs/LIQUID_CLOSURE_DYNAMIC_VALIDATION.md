# Liquid-closure dynamic validation suite

This protocol consolidates the dynamic validation of the current C++ liquid-closure stack:

- Q6 velocity projection,
- filtered low-k Q9 mass-flux projection,
- optional virial EOS pressure kick.

The suite deliberately reuses the same elliptic core for projection and filtering. It is meant to stay as close as possible to the validated MATLAB Q6/Q9 strategy: low-k correction, no extra kick limiter, and explicit diagnostics for stability.

## Scope

Two dynamic cases are included:

1. **Taylor--Green periodic vortex**, high-SNR short run.
   - Checks whether Q9/virial preserves a coherent vortex mode.
   - Fully periodic fixed box.

2. **Poiseuille channel**, periodic-x / solid-y.
   - Checks whether Q9/virial preserves the calibrated channel profile.
   - Uses solid_thermal walls and the channel elliptic operator.

The existing density-wave channel remains the preferred unit test for visible virial-gradient response. It now also reports transient response metrics such as peak velocity mode and peak virial kick.

## Why von Karman is not part of this suite yet

The branch currently contains periodic immersed-circle forced examples, but not a fully validated open-flow or sufficiently tuned von-Karman benchmark for this C++ Q6/Q9/virial closure. Including it in the consolidated liquid-closure suite would mix closure validation with wake-domain tuning, periodic re-entry effects, and cylinder-resolution sensitivity.

The recommended sequence is therefore:

1. validate Q6/Q9/virial on TG and Poiseuille;
2. keep the density-wave channel as the controlled virial-gradient test;
3. add a separate cylinder/wake protocol later, once the desired C++ cylinder-domain configuration is fixed.

## Generate required initial states

From the `matlab/` directory:

```matlab
addpath('.')
generate_taylor_green_high_snr_short_state();
generate_poiseuille_q6_channel_short_state();
```

## Run the C++ suite

From the repository root:

```bash
./scripts/build_src_mpcd_base.sh
./scripts/run_liquid_closure_dynamic_validation.sh
```

The launcher runs:

```text
Taylor--Green:
  classic
  q6
  q9_filtered
  q9_virial_K0p500_beta0p20

Poiseuille:
  classic
  q6
  q9_filtered
  q9_virial_K0p500_beta0p20
```

## Analyze

From the `matlab/` directory:

```matlab
addpath('.')
out = validate_liquid_closure_dynamic_suite('makePlots', true);
```

The output contains two tables:

- `out.taylorGreen.summary`
- `out.poiseuille.summary`

## Expected qualitative behavior

For Taylor--Green:

- Q6 and Q9 should keep the mode amplitude and correlation in the same range as the already validated runs.
- Virial kick should remain small unless density gradients become significant.
- `kBT`, particle velocity maxima, and residuals should remain stable.

For Poiseuille:

- The Q9/virial profile should remain parabolic and comparable to Q6/Q9 filtered.
- `fitR2`, `nuEff`, `q6RuntimeDivAfterEnd`, `q9RuntimeResidualEnd`, and virial kick diagnostics should be inspected together.
- A change in transport is acceptable only if stable and reproducible; the purpose here is first to detect destructive coupling.

## Density-wave virial dynamics

The density-wave validator now reports additional transient metrics:

```text
uxSinModePeakAbs
timeUxSinModePeakAbs
integralAbsUxSinMode
virialDuAppliedRmsPeak
timeVirialDuAppliedRmsPeak
virialDuAppliedMaxPeak
virialDuOverThermalRmsPeak
```

These quantities are more informative than the final value alone, because the virial force may accelerate the decay of the density mode and therefore reduce the late-time driving gradient.
