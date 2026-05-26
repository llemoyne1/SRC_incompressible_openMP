# Virial EOS piston sweep

This validation step keeps the validated moving active-domain piston and filtered
Q9 setup, then varies the optional virial EOS parameters.

The goal is deliberately modest:

- keep the virial module optional and decoupled from classic/Q6/Q9;
- verify that the EOS diagnostic follows `Pvir = Kvirial*(rho-rhoEOSRef)`;
- check that the active kick remains small and stable;
- avoid adding a limiter unless the diagnostics prove it is required.

The implementation is intended to stay close to the MATLAB integrated Q9/virial
piston workflow. The virial kick is still applied after Q6/Q9 and before the
final cell-relative thermostat, followed by exact global momentum correction.

## Sweep cases

The patch adds the following long piston parameter files:

```text
examples/params_piston_y_q9_virial_K0p005_beta0p02_solid_thermal_isothermal.kv
examples/params_piston_y_q9_virial_K0p010_beta0p02_solid_thermal_isothermal.kv
examples/params_piston_y_q9_virial_K0p020_beta0p02_solid_thermal_isothermal.kv
examples/params_piston_y_q9_virial_K0p050_beta0p02_solid_thermal_isothermal.kv
examples/params_piston_y_q9_virial_K0p100_beta0p02_solid_thermal_isothermal.kv
examples/params_piston_y_q9_virial_K0p100_beta0p05_solid_thermal_isothermal.kv
```

They all use the same moving piston:

```text
fluidYTop0 = 0.95
fluidYTopVelocity = -0.001
nSteps = 50000
```

and the same filtered Q9 setup:

```text
q9DensityRelaxationBeta = 0.0005
q9TargetFilter = elliptic_lowpass
q9LowKMaxIndex = 2
```

## Run sequence

From the repository root:

```bash
./build/src_mpcd_base examples/params_piston_y_q9_filtered_solid_thermal_isothermal.kv
./build/src_mpcd_base examples/params_piston_y_q9_virial_K0p005_beta0p02_solid_thermal_isothermal.kv
./build/src_mpcd_base examples/params_piston_y_q9_virial_K0p010_beta0p02_solid_thermal_isothermal.kv
./build/src_mpcd_base examples/params_piston_y_q9_virial_K0p020_beta0p02_solid_thermal_isothermal.kv
./build/src_mpcd_base examples/params_piston_y_q9_virial_K0p050_beta0p02_solid_thermal_isothermal.kv
./build/src_mpcd_base examples/params_piston_y_q9_virial_K0p100_beta0p02_solid_thermal_isothermal.kv
./build/src_mpcd_base examples/params_piston_y_q9_virial_K0p100_beta0p05_solid_thermal_isothermal.kv
```

From `matlab/`:

```matlab
addpath('.')
out = validate_piston_q9_virial_sweep('makePlots', true);
```

The MATLAB script uses `../runs/...` paths by default because it is intended to
be launched from `matlab/`.

## Diagnostics

The primary table reports:

```text
rhoRatio, rhoAreaResidual, massRelDrift
PkinMeanEnd, PvirMeanEnd, PtotMeanEnd
PkinMeanRatio, PtotMeanRatio
KvirialEstimate
PtotExpectedResidual
virialDuAppliedRms/Max
virialDuOverThermalRms
maxParticleAbsVy
```

`PtotMeanRatio` is computed against the first finite `PtotMean`, not necessarily
the first row of the CSV. This avoids the previous `NaN` ratio when the virial
columns are absent or not initialized in the first summary row.

A satisfactory first sweep has:

```text
massRelDrift = 0
rhoRatio = areaStart/areaEnd
PvirMeanEnd ~= Kvirial*(rhoEnd-rhoEOSRef)
PtotExpectedResidual near roundoff
kBT stable
virialDuOverThermalRms small
maxParticleAbsVy remains O(sqrt(kBT))
```
