# 0104 — Periodic cylinder startup visual check

This patch adds a short, visual, periodic-cylinder startup suite.  It is meant
to inspect the first instants of the immersed cylinder case before running any
long physical validation.

## Scope

No C++ kernel change is introduced by this patch.  It only adds:

- short parameter files for Q6, Q9 and Q9+virial;
- a WSL/bash runner;
- a MATLAB visual report helper producing visible figures and PNG contact sheets.

The case remains fully periodic in x and y.  This deliberately avoids mixing the
immersed-solid boundary checks with inlet/outlet effects.

## Default case

- domain: `Lx=2`, `Ly=1`
- grid: `Nx=96`, `Ny=48`
- occupancy: `gamma=20`
- cylinder: `Cx=0.5`, `Cy=0.5`, `R=0.12`
- boundary conditions: periodic on all sides
- body acceleration: `bodyAccelerationX=0.001`
- default run length: `nSteps=200`
- default summary/dump cadence: every 10 steps

Q9 uses:

- `q9ReferenceGamma = 20`
- `q9ImmersedSolidHaloCells = 0`
- `q9DiagnosticFieldDumpEnable = true`
- binary sidecars at the same cadence as state dumps.

## Run

From the repository root:

```bash
bash scripts/run_periodic_cylinder_startup_visual_0104.sh
```

A shorter test can be launched with:

```bash
CASE_STEPS=100 SUMMARY_EVERY=10 DUMP_STATE_EVERY=10 \
  bash scripts/run_periodic_cylinder_startup_visual_0104.sh
```

By default the runner launches Q9 and Q9+virial.  Q6 can be added with:

```bash
RUN_Q6=1 bash scripts/run_periodic_cylinder_startup_visual_0104.sh
```

The MATLAB report is enabled by default when `matlab` is on `PATH`.  It opens
visible figures and writes PNG files in each run directory under `visual_0104/`.
To disable the report:

```bash
MAKE_VISUAL_REPORT=0 bash scripts/run_periodic_cylinder_startup_visual_0104.sh
```

To generate the report later:

```matlab
cd matlab
make_periodic_cylinder_startup_visual_report_0104({}, 'maxFrames', 8, 'frameStride', 1, 'visible', true);
```

## Visual fields

The report writes contact sheets for:

- `N`
- `speed`
- `omega`
- `q9CorrectionLimiterRatio`
- `q9LowMassSuppressed`
- `q9SafetyActive`
- `q9ImmersedSolidAdjacentActive`
- `q9ImmersedSolidCut`

Filtering is intentionally not applied in this report, so early startup artifacts
are not hidden.

## Expected checks

For Q9 and Q9+virial:

- `q9ImmersedHaloExcludedCells = 0`
- `q9ImmersedSolidActiveAdjacentCells > 0`
- `q9ImmersedSolidLeakMassFluxRms = 0` or machine zero
- `q9ImmersedSolidClosedFaceFluxEnforcedFaces > 0`
- no persistent `q9LowMassSuppressed` patch near the cylinder
- no spurious inactive annulus around the cylinder in `q9ImmersedSolidAdjacentActive`
- sidecars exist: `q9_diagnostics_step_*.q9bin`

For Q9+virial, also check that the normal-kick clipping diagnostics are present
and finite.
