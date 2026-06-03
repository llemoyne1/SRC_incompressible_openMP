# 0152 — Closed-capacity wall-load validation scripts

This patch adds a small validation suite for the wall-load objective introduced in 0151.
The goal is to verify whether the reconstructed closed-capacity pressure

```text
P_wall = P_kin + P_vir
```

can be interpreted as a normal load on solid walls before any deformable-wall coupling is attempted.

The key validation case is deliberately simpler than the inlet-only pressurization run: a closed box is initialized with a uniform mass overfill and no inlet.  In that situation the virial pressure should be spatially almost uniform, the four wall pressures should be similar, and the net force integrated over all walls should be close to zero.

## Files added

```text
matlab/prepare_closed_capacity_uniform_overfill_0152.m
matlab/prepare_closed_capacity_uniform_overfill_suite_0152.m
matlab/analyze_closed_capacity_wall_load_validation_0152.m
scripts/run_closed_capacity_wall_load_validation_0152.sh
doc/README_0152_CLOSED_CAPACITY_WALL_LOAD_VALIDATION.md
```

## Run the static wall-load validation

From the repository root:

```bash
bash scripts/build_src_mpcd_base.sh
bash scripts/run_closed_capacity_wall_load_validation_0152.sh
```

The runner uses the following mass factors by default:

```text
1.00 1.02 1.05 1.10
```

They can be changed with:

```bash
CAP_STATIC_MASS_FACTORS="1.00 1.01 1.02 1.05" \
CAP_STEPS=300 \
bash scripts/run_closed_capacity_wall_load_validation_0152.sh
```

If MATLAB is available in `PATH`, missing initial states are generated automatically with `matlab -batch`.  Otherwise, generate the states manually:

```matlab
cd matlab
prepare_closed_capacity_uniform_overfill_suite_0152( ...
    'outputDir', '../init/closed_capacity_wall_load_0152', ...
    'Lx', 1.0, 'Ly', 1.0, ...
    'Nx', 48, 'Ny', 48, ...
    'gamma', 20, ...
    'massFactors', [1.00 1.02 1.05 1.10], ...
    'capacityMultiplier', 1.10, ...
    'kBT', 0.0, ...
    'makePreview', true);
cd ..
```

Then rerun the shell script.

## Analyze the results

From the repository root:

```matlab
cd matlab
T = analyze_closed_capacity_wall_load_validation_0152( ...
    '../runs/closed_capacity_wall_load_validation_0152');
```

The analysis writes:

```text
runs/closed_capacity_wall_load_validation_0152/matlab_closed_capacity_wall_load_0152/closed_capacity_wall_load_0152_summary.csv
runs/closed_capacity_wall_load_validation_0152/matlab_closed_capacity_wall_load_0152/closed_capacity_wall_load_0152_analysis.mat
runs/closed_capacity_wall_load_validation_0152/matlab_closed_capacity_wall_load_0152/closed_capacity_wall_load_0152_summary.png
runs/closed_capacity_wall_load_validation_0152/matlab_closed_capacity_wall_load_0152/closed_capacity_wall_load_0152_time_traces.png
```

## Expected interpretation

For the uniform static overfill tests:

- `wallPressureVirialMeanAll` and `wallPressureTotalMeanAll` should increase with overfill.
- `wallPressureTotalLeft`, `Right`, `Bottom`, and `Top` should be close to one another.
- `wallForceImbalanceRatio = |F_wall| / (p_mean L_solid)` should remain small.
- `wallPressureFaceCv` and `wallPressureFaceRangeRelative` should remain small.

This validates the conversion from bulk virial pressure to a wall-normal load in the simplest symmetric setting.

The inlet-only run remains a dynamic asymmetric pressurization test.  There, nonzero net wall force is possible because the inlet segment breaks the symmetry and the pressure field is not necessarily uniform.  The static suite isolates the wall-load diagnostic from inlet-driven transients.

## 0153 compatibility note

The static validation is virial-only by default and intentionally allows `CAP_KBT=0.0`.  To avoid parser failures with solid-wall thermal coupling, the runner now disables wall VP accommodation and the thermostat by default:

```text
wallAccommodation = 0.0
thermostatEnable = false
resamplingThermalRenormalizationEnable = false
```

This does not disable the wall-load diagnostic: `Pkin + Pvir` is still reconstructed from cell fields and integrated on the solid wall faces.  For finite-temperature wall-coupled variants, set for example:

```bash
CAP_KBT=0.001 CAP_WALL_ACCOMMODATION=1.0 CAP_THERMOSTAT_ENABLE=true \
CAP_THERMAL_RENORM_ENABLE=true \
bash scripts/run_closed_capacity_wall_load_validation_0152.sh
```

## Parameters used by the runner

The runner uses closed-capacity response, but disables the virial kick in the static cases:

```text
closedCapacityResponseEnable = true
closedCapacityVirialKickEnable = false
closedCapacityInletMassFluxEnable = false
```

This isolates the wall-load diagnostic.  The pressure is reconstructed from the overfilled mass field and integrated on solid walls, but no pressure-gradient velocity kick is applied.

The resampling remains active with `resamplingWetMaskMode = active_domain`, so the test also checks that the mass-remap target introduced in 0149 preserves the uniform overfill instead of erasing it.
