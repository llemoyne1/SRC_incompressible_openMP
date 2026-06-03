# 0103 — Q6 immersed-solid closed-face diagnostic cleanup

This micro-patch aligns the Q6 immersed-solid leakage diagnostics with the Q9
face/cell convention introduced in 0101.

## Motivation

The periodic-cylinder smoke showed a clean Q9 closure after the explicit
closed-face flux enforcement, but the Q6 immersed-solid projected-flux leak
remained non-zero.  This patch makes the Q6 diagnostic semantic explicit:

- measure the reconstructed closed-face flux before geometric closure;
- enforce zero projected flux on true immersed-solid internal faces;
- report the remaining projected-flux leak after closure.

The patch does not introduce any halo or volumetric exclusion.  Fluid cells
adjacent to the immersed solid remain active.

## New Q6 runtime columns

The following columns are added to `summary_runtime.csv`:

- `q6ImmersedSolidLeakFaceCount`
- `q6ImmersedSolidAppliedLeakBeforeClosureRms`
- `q6ImmersedSolidAppliedLeakBeforeClosureMaxAbs`
- `q6ImmersedSolidClosedFaceFluxEnforcedFaces`
- `q6ImmersedSolidClosedFaceFluxEnforcedRms`
- `q6ImmersedSolidClosedFaceFluxEnforcedMaxAbs`

The existing columns

- `q6ImmersedSolidLeakProjectedFluxRms`
- `q6ImmersedSolidLeakProjectedFluxMaxAbs`

now describe the effective projected flux after the explicit immersed-solid
closed-face closure.

## Additional cleanup

The unused helper `accumulate_q9_solid_leak_value()` is removed from
`src/q9_projection_adapter.cpp`, eliminating the corresponding compiler warning.

## Suggested smoke

```bash
bash scripts/build_src_mpcd_base.sh

CASE_STEPS=75 SUMMARY_EVERY=25 DUMP_STATE_EVERY=25 \
  bash scripts/run_periodic_cylinder_face_cell_smoke_0102.sh
```

Expected smoke-level checks:

- no compiler warning about `accumulate_q9_solid_leak_value()`;
- `q6ImmersedSolidAppliedLeakBeforeClosureRms` reports the pre-closure Q6 flux;
- `q6ImmersedSolidLeakProjectedFluxRms` is near zero after closure;
- Q9 diagnostics remain unchanged, with `q9ImmersedSolidLeakMassFluxRms = 0`.
