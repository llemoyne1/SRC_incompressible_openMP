# Optional virial EOS pressure kick for the moving piston

This branch keeps the compressible, Q6 and Q9 paths independent.  The virial
EOS module is optional and disabled unless requested explicitly, or unless
`method = q9_virial` is used.

The implementation is intentionally close to the validated MATLAB routine
`mpcd_apply_virial_pressure_kick_channel.m`.

## Formulation

The diagnostic EOS pressure is

```text
PvirEOS = Kvirial * (rho - rhoEOSRef)
PtotEOS = Pkin + PvirEOS
```

The optional active kick uses a possibly different drive reference density:

```text
Pdrive = Pkin + Kvirial * (rho - rhoDriveRef)
du     = - virialBeta * dt/rhoKick * grad(Pdrive)
```

The velocity increment is interpolated with the same nearest-cell convention
used by Q6/Q9 adapters and is followed by an exact global momentum correction.
The final cell-relative thermostat is then applied as usual.

## Default piston settings

The example

```text
examples/params_piston_y_q9_virial_solid_thermal_isothermal.kv
```

uses the validated filtered-Q9 piston setup plus

```text
method = q9_virial
virialDiagnosticsEnable = true
virialKickEnable = true
Kvirial = 0.01
virialBeta = 0.02
virialRhoEOSRefMode = initial_physical_density
virialRhoUniformMode = reference_gamma_current_volume
virialDriveTargetMode = current_uniform
virialRhoKickMode = uniform_now
```

The values `Kvirial=0.01`, `virialBeta=0.02` are deliberately mild and match the
order used in the MATLAB integrated validation suite.  No additional velocity
limiter is introduced in this C++ step; diagnostics should indicate whether the
kick remains small.

## Diagnostics

The runtime summary records the key EOS and kick quantities:

```text
virialEnabled
virialKickApplied
virialRhoMean
virialRhoEOSRef
virialRhoUniformNow
virialRhoDriveRef
virialRhoDefectRms
PkinMean
PvirMean
PtotMean
PdriveMean
gradPdriveRms
virialDuAppliedRms
virialDuAppliedMaxAbs
virialDuOverThermalRms
virialMomentumResidualBeforeCorrection
virialMomentumResidualAfterCorrection
```

For piston runs, the important first checks are:

```text
massRelDrift = 0
rhoRatio follows areaStart/areaEnd
kBT remains stable
PtotMean changes consistently with compression
virialDuAppliedMaxAbs remains small compared with sqrt(kBT)
virialMomentumResidualAfterCorrection remains near zero
```

## Run sequence

From the repository root:

```bash
./build/src_mpcd_base examples/params_piston_y_solid_thermal_isothermal.kv
./build/src_mpcd_base examples/params_piston_y_q6_solid_thermal_isothermal.kv
./build/src_mpcd_base examples/params_piston_y_q9_filtered_solid_thermal_isothermal.kv
./build/src_mpcd_base examples/params_piston_y_q9_virial_solid_thermal_isothermal.kv
```

From `matlab/`:

```matlab
addpath('.')
out = validate_piston_q9_virial_active_domain('makePlots', true);
```

The MATLAB script assumes paths of the form `../runs/...` because it is intended
to be launched from `matlab/`.
