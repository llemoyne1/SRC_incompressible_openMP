# 0101 — Q9 immersed-solid closed-face flux enforcement

## Purpose

This patch fixes the immersed-circle smoke failure observed after 0100, where Q9 reported a large solid leak on cell-closed faces while the cut-face leak was zero. The failure mode is not a low-mass limiter issue and not a cut-face issue: it is a face-ownership issue for cell-closed immersed faces, especially when the face owner is inactive/solid and the neighbour is active/fluid.

The numerical intent remains unchanged:

- fluid cells adjacent to the immersed solid stay active;
- no Q9 halo is introduced;
- Q9 correction is allowed in the fluid up to the wall;
- the normal mass flux through immersed solid faces is forced to zero.

## Implementation

After Q9 converts the projected correction flux into cell velocity kicks and reconstructs the applied mass-flux field, the code now performs an explicit geometric closure on immersed solid boundary faces:

```text
projectedMassFlux(face) = 0
appliedCorrectionFlux(face) = -baseMassFlux(face)
```

This closure is applied only to internal immersed-boundary faces:

- one side active/fluid and the other side inactive/solid; or
- a cut-closed face between active cells.

Domain high-side faces in non-periodic/open-boundary cases are deliberately skipped by this immersed-solid closure, so inlet/outlet handling remains controlled by the open-boundary logic.

The leak diagnostic was also tightened: it now measures only immersed solid boundary faces, not solid-solid interior faces. This avoids counting irrelevant flux carried by occasional particles still inside fully solid cells.

## New runtime diagnostics

The following columns are appended to `summary_runtime.csv`:

```text
q9ImmersedSolidLeakFaceCount
q9ImmersedSolidAppliedLeakBeforeClosureRms
q9ImmersedSolidAppliedLeakBeforeClosureMaxAbs
q9ImmersedSolidClosedFaceFluxEnforcedFaces
q9ImmersedSolidClosedFaceFluxEnforcedRms
q9ImmersedSolidClosedFaceFluxEnforcedMaxAbs
```

Expected interpretation:

- `q9ImmersedSolidAppliedLeakBeforeClosure*` records the residual leak before the geometric closed-face cleanup;
- `q9ImmersedSolidClosedFaceFluxEnforced*` records the amount removed by the cleanup;
- the existing `q9ImmersedSolidLeakMassFluxRms` is measured after cleanup and should return near roundoff for closed immersed faces.

## Recommended smoke test

```bash
CASE_STEPS=75 SUMMARY_EVERY=25 DUMP_STATE_EVERY=25 \
  bash scripts/run_immersed_circle_face_cell_smoke_0100.sh
```

Expected fast criteria for Q9 and Q9+virial:

```text
q9ImmersedHaloExcludedCells = 0
q9ImmersedSolidActiveAdjacentCells > 0
q9ImmersedSolidLeakMassFluxRms ~ roundoff
q9ImmersedSolidAppliedLeakBeforeClosureRms may be O(1e-1) on the old failing circle smoke
q9ImmersedSolidClosedFaceFluxEnforcedRms should match the pre-closure leak scale
```

This patch is diagnostic/closure-level. It does not add an exclusion halo and does not change the classic compressible path.
