# 0098 — Immersed solid face/cell mask for Q6/Q9/virial

This patch starts the immersed-solid boundary cleanup after the inlet/outlet
validation branch.

## Numerical intent

The immersed solid is treated as a cell/face finite-volume constraint, not as a
volumetric dead halo around the obstacle.

Nominal model:

- solid cells are inactive;
- fluid cells remain active, including cells adjacent to the solid;
- cut cells remain active when their fluid fraction passes the configured
  `projectionImmersedSolidFluidFractionThreshold`;
- fluid-fluid faces remain open;
- fluid-solid and cut solid-normal faces are closed by the face mask;
- Q6 and Q9 therefore enforce zero normal flux through the solid through the
  same generic elliptic face operator;
- the virial module uses the same active-cell mask and boundary-aware pressure
  gradient sampling.

This is intentionally different from the older conservative Q9 halo strategy.
A Q9 halo can still be requested for explicit debug or conservative runs through
`q9ImmersedSolidHaloCells>0`, but it is not the nominal immersed-solid model and
will be reported as a warning by the executable.

## Added diagnostics

The immersed-solid projection mask now carries:

- `cutCells`: cells intersected by the immersed geometry;
- `activeCutCells`: cut cells that remain active in the operator;
- `activeSolidAdjacentCells`: active fluid cells touching the immersed solid by
  an inactive neighbour or a cut closed face;
- `cutCell`: per-cell flag;
- `activeSolidAdjacentCell`: per-cell flag.

These counters are propagated to Q6, Q9, virial diagnostics and appended to
`summary_runtime.csv`.

Q9 diagnostic sidecars now also contain the following optional per-cell flags:

- `q9ImmersedSolidActive`;
- `q9ImmersedSolidCut`;
- `q9ImmersedSolidAdjacentActive`.

The MATLAB reader remains backward compatible with previous `.q9bin` sidecars
that had only five flag fields.  New sidecars write eight flag fields.

## MATLAB visualization fields

The following fields can be inspected directly with
`play_smpcd_filtered_animation`:

```matlab
play_smpcd_filtered_animation(runDir, 'field', 'q9ImmersedSolidActive')
play_smpcd_filtered_animation(runDir, 'field', 'q9ImmersedSolidCut')
play_smpcd_filtered_animation(runDir, 'field', 'q9ImmersedSolidAdjacent')
play_smpcd_filtered_animation(runDir, 'field', 'q9SafetyActive')
play_smpcd_filtered_animation(runDir, 'field', 'q9LowMassSuppressed')
play_smpcd_filtered_animation(runDir, 'field', 'q9LimiterRatio')
```

For sidecar-backed Q9 masks, MATLAB now prefers the exact C++ `q9SafetyActive`
field instead of reconstructing the Q9 active mask from parameters.  This avoids
misrepresenting the true face/cell operator state near immersed solids and open
boundaries.

## Recommended nominal parameters

```text
immersedSolidEnable = true
projectionImmersedSolidMaskEnable = true
projectionImmersedSolidCloseCutFaces = true
projectionAllowUnmaskedImmersedSolid = false
q9ImmersedSolidHaloCells = 0
q9OpenBoundaryExclusionCells = 0
virialOpenBoundaryExclusionCells = 0
```

For Q9/virial runs with diagnostics:

```text
q9DiagnosticFieldDumpEnable = true
q9DiagnosticFieldDumpFormat = binary
q9DiagnosticFieldDumpEvery = <same cadence as state dumps or finer>
```

## First validation checks

For an immersed circle or obstacle run, check:

- `q9ImmersedHaloExcludedCells == 0` in nominal runs;
- `q9ImmersedSolidActiveAdjacentCells > 0` when the solid boundary cuts through
  the fluid grid;
- `q9ImmersedSolidLeakMassFluxRms` remains small;
- `q9ImmersedSolidLeakCutMassFluxRms` and
  `q9ImmersedSolidLeakCellClosedMassFluxRms` separate geometric cut-face leakage
  from cell-solid closure leakage;
- no thick inactive Q9 shell appears around the obstacle in MATLAB.

