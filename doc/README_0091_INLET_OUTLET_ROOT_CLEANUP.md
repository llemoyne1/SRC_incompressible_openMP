# 0091 - Root README and inlet/outlet script cleanup

## Scope

This note documents the final cleanup patch for the `feature/inlet-outlet`
branch after validation of the full open-channel inlet/outlet cases.

The patch intentionally does not modify the numerical core:

- no change in `src/`;
- no change in `include/`;
- no new FFT path;
- no change to the generic elliptic projection operator;
- no removal of the classical compressible mode.

The changes are limited to user-facing repository organization:

- new root `README.md` reflecting the actual `feature/inlet-outlet` status;
- cleaned full-channel tapered-flat runner labels;
- cleaned `run_open_channel_jet.sh` as a physical segmented-aperture prototype;
- documented legacy status of the early 0083 segmented aperture script.

## Frozen validated inlet/outlet domain

The branch is validated for channels without immersed solids:

1. full inlet/outlet with slip/specular horizontal walls;
2. full inlet/outlet with VP/no-slip horizontal walls and Poiseuille mean profile;
3. full inlet/outlet with VP/no-slip horizontal walls and tapered-flat profile.

The nominal open-boundary settings remain:

```text
q9OpenBoundaryExclusionCells = 0
virialOpenBoundaryExclusionCells = 0
```

This is a physical/numerical conclusion of the validation campaign: non-zero
open-boundary exclusions create an artificial active/inactive interface near the
outlet and may behave like a numerical wall.

## Q9 nominal limiter and low-mass policy

The nominal Q9 limiter is:

```text
q9CorrectionLimiterMode = thermal_soft
q9CorrectionVelocityLimiterOverThermal = 0.5
```

For `kBT = 0.0025`, the corresponding velocity increment cap is:

```text
dU_limit = 0.5 * sqrt(0.0025) = 0.025
```

The low-mass policy is gamma-relative:

```text
q9LowMassRampStartOverGamma = 0.05
q9LowMassRampEndOverGamma = 0.40
q9MassFloorForCorrectionOverGamma = 0.40
q9MinCellMassForCorrectionOverGamma = 0.40
```

## Script cleanup

### `run_open_channel_full_io_vp_tapered_flat_q9_virial_excl0_0089.sh`

Only labels were corrected.  The generated case names now say
`tapered_flat` instead of `poiseuille`, matching the actual inlet profile:

```text
inletVelocitySpatialProfile = flat_taper_y
inletVelocityWallTaperCells = 2.0
```

### `run_open_channel_jet.sh`

The script is now a clear physical segmented-aperture prototype.  Its default
geometry is a narrow left inlet slit and a wider right outlet window:

```text
openBoundaryApertureEnable = true
leftOpenYMin = 0.40
leftOpenYMax = 0.60
rightOpenYMin = 0.20
rightOpenYMax = 0.80
```

The default spatial velocity profile is `uniform`, because the aperture itself
already defines the slit/nozzle geometry.  Other profiles remain available for
stress tests:

```bash
INLET_VELOCITY_SPATIAL_PROFILE=flat_taper_y ./scripts/run_open_channel_jet.sh
INLET_VELOCITY_SPATIAL_PROFILE=poiseuille_y_mean ./scripts/run_open_channel_jet.sh
```

### `run_poiseuille_segmented_inlet_outlet_softlimited_q9_0083.sh`

The script is kept for reproducibility but marked as a legacy segmented-aperture
stress test.  Its default Q9/virial open-boundary exclusions were set to zero to
avoid reintroducing the pre-0087 active/inactive outlet impedance.

## Next development direction

The next clean task is to build a small documented family of physical segmented
inlet/outlet cases:

- centered slit inlet, wide outlet;
- symmetric slit inlet/outlet;
- wider nozzle inlet/outlet;
- optional tapered profiles as stress tests;
- classic/q6/q9/q9_virial comparisons with the same geometry.

This should remain separate from the canonical Poiseuille validation and from
the immersed-solid boundary-mask branch.
