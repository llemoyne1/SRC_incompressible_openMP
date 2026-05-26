# 0090 — Inlet/outlet validation status for `feature/inlet-outlet`

## Scope

This note closes the current inlet/outlet development sequence on branch `feature/inlet-outlet` for the C++ SRC/MPCD code `SRC_incompressible_openMP`.

The validated scope is deliberately limited to open-boundary channel configurations without immersed internal solids. Immersed/embedded solid handling, especially Q9/virial behavior near solid walls and obstacle-generated compression, is now identified as a separate development axis and should move to a dedicated branch/chat.

## Constraints kept during the sequence

- No `.patch` files.
- Differential archives only, named `*_files_only.zip`.
- Work remained on branch `feature/inlet-outlet`.
- The classic compressible mode remained available.
- Periodic/channel validation paths were not intentionally broken.
- The generic elliptic operator remained the preferred projection backend.
- No new FFT-specific inlet/outlet path was introduced.
- New markdown documentation was placed in `doc/`, except for root `README.md` if updated separately.

## Main conclusions

### 1. Hard inlet and free/passive outlet can work, but Q9 must remain active up to open boundaries

The key failure mode observed during the open-channel tests was not the hard inlet itself, nor the outlet alone, nor the virial closure alone.

The dominant problem was the historical exclusion layer near open boundaries:

```text
q9OpenBoundaryExclusionCells > 0
virialOpenBoundaryExclusionCells > 0
```

This created an active/inactive interface for Q9/virial near the outlet. That interface behaved like a numerical impedance or internal wall, producing vertical density bands, recirculation-like structures, large local populations, and degraded mass transport.

The decisive diagnostic was the full-inlet/full-outlet slip-channel sweep:

```text
q9OpenBoundaryExclusionCells = 0
virialOpenBoundaryExclusionCells = 0
```

With zero open-boundary exclusion, the full Q9+virial case became clean: mass remained near target, outlet/inlet flux balanced, no outlet density band persisted, and Q9 operated in a mild correction regime.

### 2. The thermal soft limiter is a valid nominal stabilizer

The unbounded Q9 correction kick can become ballistic in hard-inlet/open-outlet transients, even in simple open-channel cases. A fixed tiny limiter such as `0.003` is too conservative and can prevent Q9 from acting; no limiter is too aggressive and can generate violent kicks.

The adopted nominal form is a thermal-scale soft limiter:

```text
q9CorrectionLimiterMode = thermal_soft
q9CorrectionVelocityLimiterOverThermal = 0.5
```

For `kBT = 0.0025`, this gives:

```text
dU_limit = 0.5 * sqrt(kBT) = 0.025
```

This keeps Q9 active but prevents ballistic correction velocities. It should be regarded as the nominal limiter for open-boundary Q9 runs unless a specific test intentionally disables it.

### 3. Low-mass thresholds should scale with gamma

The Q9 low-mass safety thresholds must not be fixed as absolute particle counts when `gamma` changes. The implemented relative form preserves the previous `gamma=20` behavior while extending it consistently:

```text
q9LowMassRampStartOverGamma         = 0.05
q9LowMassRampEndOverGamma           = 0.40
q9MassFloorForCorrectionOverGamma   = 0.40
q9MinCellMassForCorrectionOverGamma = 0.40
```

Examples:

```text
gamma = 20 -> start=1.0, end/floor/min=8
gamma = 30 -> start=1.5, end/floor/min=12
gamma = 40 -> start=2.0, end/floor/min=16
```

### 4. Ramping the inlet velocity is physically and numerically appropriate

A hard inlet that switches from rest to `Uin = 0.05` instantaneously creates an impulsive transient. The inlet velocity ramp is therefore part of the nominal open-channel setup:

```text
inletVelocityRampEnable = true
inletVelocityRampProfile = smoothstep
inletVelocityRampStartTime = 0.0
inletVelocityRampEndTime = 40.0    # typical long-run value for Lx=2, Uin=0.05
```

The ramp factor is applied coherently to:

- particle hard-inlet velocities;
- Q6 open-boundary fluxes;
- Q9 open-boundary mass fluxes.

### 5. Full-height inlet/outlet with slip walls is validated

The cleanest baseline is:

```text
bcLeft   = inlet
bcRight  = outlet
bcBottom = specular / slip
bcTop    = specular / slip
q9OpenBoundaryExclusionCells = 0
virialOpenBoundaryExclusionCells = 0
method = q9_virial
```

With `gamma=30`, `Uin=0.05`, ramped inlet, thermal soft limiter, and full-height open boundaries, the run remains stable over long durations. It balances inlet/outlet flux and does not form the previous outlet density band.

This validates the basic inlet/outlet machinery independently of no-slip wall complications.

### 6. Full-height inlet/outlet with VP/no-slip walls and a Poiseuille-compatible inlet profile is validated

The next validated level is:

```text
bcBottom = solid
bcTop    = solid
wallAccommodation = 1.0
inletVelocitySpatialProfile = poiseuille_y_mean
q9OpenBoundaryExclusionCells = 0
virialOpenBoundaryExclusionCells = 0
method = q9_virial
```

With the Poiseuille-compatible imposed profile, the channel reaches a clean parabolic profile and stable density/temperature diagnostics. This is the strongest validation case for open inlet/outlet combined with VP/no-slip walls.

### 7. VP/no-slip walls with a strict flat inlet is stable but locally less clean

The strict flat inlet remains a useful stress test, but it is physically incompatible with no-slip walls at the entry. It can generate wall-attached pockets and degrade global statistics even when the mass and flux balances are good.

It should not be the nominal validation profile for VP/no-slip walls.

### 8. A tapered flat inlet is the preferred “developing-flow” flat-profile variant

The final developing-flow variant uses:

```text
inletVelocitySpatialProfile = flat_taper_y
inletVelocityWallTaperCells = 2.0
```

It preserves an approximately flat core while tapering smoothly toward zero near the VP/no-slip walls. Diagnostics show that the core remains clean, wall pockets are reduced, the outlet band does not reappear, and global mass/temperature remain controlled.

This should be the recommended flat-profile open-channel inlet for VP/no-slip walls.

## Recommended nominal parameter block for validated inlet/outlet channel runs

```text
method = q9_virial

projectionEnable = true
projectionOperator = elliptic_fv_cg
q6ProjectionStrength = 1.0
projectionMaxIterations = 500
projectionTolerance = 1.0e-10
projectionMomentumCorrectionEnable = true

q9MassFluxProjectionEnable = true
q9MassFluxProjectionStrength = 1.0
q9DensityRelaxationBeta = 0.0005
q9TargetFilter = elliptic_lowpass
q9LowKMaxIndex = 2
q9EllipticLowPassPasses = 1
q9MomentumCorrectionEnable = true

q9OpenBoundaryExclusionCells = 0
virialOpenBoundaryExclusionCells = 0

q9CorrectionLimiterMode = thermal_soft
q9CorrectionVelocityLimiterOverThermal = 0.5
q9CorrectionLimiterThermalKBT = 0.0

q9LowMassTreatment = ramp_floor
q9ReferenceGamma = gamma
q9LowMassRampStartOverGamma = 0.05
q9LowMassRampEndOverGamma = 0.40
q9MassFloorForCorrectionOverGamma = 0.40
q9MinCellMassForCorrectionOverGamma = 0.40

inletVelocityRampEnable = true
inletVelocityRampProfile = smoothstep
inletVelocityRampInitialFactor = 0.0
inletVelocityRampFinalFactor = 1.0
```

For VP/no-slip walls, use one of:

```text
inletVelocitySpatialProfile = poiseuille_y_mean    # established channel validation
inletVelocitySpatialProfile = flat_taper_y         # developing-flow validation
inletVelocityWallTaperCells = 2.0                  # for flat_taper_y
```

## Important notes on segmented inlet/outlet apertures

Segmented apertures are implemented and useful, but they should not be used to “fix” the basic Poiseuille/channel validation. Segmenting a full outlet creates a real slot/outlet geometry with additional aperture corners and can generate its own contraction/recirculation phenomena.

For canonical open-channel validation, use full-height inlet/outlet. For slot, jet, nozzle, or partial outlet cases, treat segmented apertures as separate physical geometries requiring dedicated diagnostics.

## Immersed-solid status

The backward-step and obstacle experiments were crucial diagnostically, but they should not be used to validate `feature/inlet-outlet` itself.

They revealed a separate immersed-solid issue:

- Q9 must not be disabled around solids in a way that removes correction precisely where compression forms.
- A solid halo can protect stability but also prevents Q9/virial from acting at the wall-adjacent fluid cells.
- The correct future direction is a face/cell masked Q9/virial treatment: fluid cells adjacent to solids remain active; fluid-solid faces impose no normal corrective flux.

This should move to a dedicated branch, for example:

```bash
git checkout feature/inlet-outlet
git pull
git checkout -b feature/q9-immersed-solid-boundary
```

## Suggested commit message

```text
0090 document validated inlet-outlet configuration

- summarize final hard-inlet/free-outlet validation sequence
- document thermal soft Q9 limiter and gamma-relative low-mass thresholds
- document that Q9/virial must remain active up to open boundaries
- record validated full-IO slip, VP Poiseuille-profile, and VP tapered-flat cases
- separate remaining immersed-solid/Q9 wall-adjacent work into a future branch
```
