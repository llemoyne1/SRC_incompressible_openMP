# 0102 — Periodic-cylinder face/cell smoke runner

This patch adds a short periodic-cylinder smoke suite for the immersed-solid face/cell formulation.
The geometry is a fixed immersed circular solid in a fully periodic 2-D domain, i.e. the cross-section of a periodic cylinder array.

The goal is deliberately limited: isolate immersed-solid behavior without inlet/outlet boundary conditions.
This is not yet a physical von Karman validation.

## Files

- `examples/params_periodic_cylinder_classic_smoke_96x48_0102.kv`
- `examples/params_periodic_cylinder_q6_smoke_96x48_0102.kv`
- `examples/params_periodic_cylinder_q9_smoke_96x48_0102.kv`
- `examples/params_periodic_cylinder_q9_virial_smoke_96x48_0102.kv`
- `scripts/run_periodic_cylinder_face_cell_smoke_0102.sh`

## Default case

- `Lx = 2.0`, `Ly = 1.0`
- `Nx = 96`, `Ny = 48`
- `gamma = 20`
- fixed cylinder: `Cx = 0.5`, `Cy = 0.5`, `R = 0.12`
- fully periodic boundaries
- mild forcing: `bodyAccelerationX = 0.002`
- default duration: `150` steps
- summary/dump cadence: `25` steps

The runner generates the initial state with MATLAB if needed, excluding particles from the cylinder.

## Run

```bash
bash scripts/run_periodic_cylinder_face_cell_smoke_0102.sh
```

Shorter smoke:

```bash
CASE_STEPS=75 SUMMARY_EVERY=25 DUMP_STATE_EVERY=25 \
  bash scripts/run_periodic_cylinder_face_cell_smoke_0102.sh
```

Include the classic reference:

```bash
RUN_CLASSIC=1 bash scripts/run_periodic_cylinder_face_cell_smoke_0102.sh
```

## Expected checks

For Q9 and Q9+virial, the important checks are:

- `q9ImmersedHaloExcludedCells = 0`
- `q9ImmersedSolidActiveAdjacentCells > 0`
- `q9ImmersedSolidActiveCutCells > 0`
- `q9ImmersedSolidLeakMassFluxRms ≈ 0` after 0101 closed-face enforcement
- `q9ImmersedSolidAppliedLeakBeforeClosureRms` may be non-zero and quantifies the pre-enforcement residual
- `q9bin_count > 0`

For Q9+virial, the `virialImmersedSolidNormalKickClipped*` columns should be present. Their values may be small or zero on very short runs depending on the local density gradient.

## Interpretation

This runner keeps all external boundaries periodic on purpose. It validates the immersed-cylinder mask, Q9 closed-face mass-flux enforcement, and virial normal-kick clipping without mixing in inlet/outlet effects.


## Note 0102b

For the periodic Q9 and Q9+virial cases, `q9ReferenceGamma = 20` is set explicitly because there is no inlet from which `inletTargetOccupancy` could define the reference mass. This is required by the relative low-mass thresholds such as `q9MinCellMassForCorrectionOverGamma`.

## 0102c parameter correction

The q9_virial periodic-cylinder smoke uses only parameter keys supported by
`src/params_io_base.cpp`. The invalid legacy key `virialReferenceDensity` was
removed. The virial reference modes are now stated explicitly with supported
keys:

```text
virialRhoEOSRefMode = initial_physical_density
virialRhoUniformMode = reference_gamma_current_volume
virialDriveTargetMode = current_uniform
virialRhoKickMode = uniform_now
virialRhoKickMinFraction = 0.1
```

For periodic Q9/Q9-virial runs, `q9ReferenceGamma = 20` is explicitly set
because there is no inlet occupancy from which to infer the reference gamma.
