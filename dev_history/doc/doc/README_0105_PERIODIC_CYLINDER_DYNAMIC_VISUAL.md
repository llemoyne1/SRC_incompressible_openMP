# 0105 — Periodic immersed-cylinder dynamic visual check

This case is an intermediate development validation for the immersed-solid
face/cell formulation after the 0101 Q9 closed-face flux enforcement and the
0103 Q6 diagnostic cleanup.

It is still fully periodic.  The goal is to make the cylinder dynamics more
visible than in the 0104 startup check, without mixing the result with
inlet/outlet boundary conditions.

## Files

```text
examples/params_periodic_cylinder_q9_dynamic_visual_96x48_0105.kv
examples/params_periodic_cylinder_q9_virial_dynamic_visual_96x48_0105.kv
scripts/run_periodic_cylinder_dynamic_visual_0105.sh
matlab/make_periodic_cylinder_dynamic_visual_report_0105.m
doc/README_0105_PERIODIC_CYLINDER_DYNAMIC_VISUAL.md
```

## Default case

```text
Lx = 2, Ly = 1
Nx = 96, Ny = 48
gamma = 20
immersed circle: C = (0.5, 0.5), R = 0.12
BCs = periodic on all sides
bodyAccelerationX = 0.005
nSteps = 3000
summaryEvery = 50
dumpStateEvery = 100
```

The default launcher runs:

```text
q9
q9_virial
```

The case is not intended as a final von Karman benchmark.  It is a controlled
periodic visual/dynamic stress test for the immersed-solid mask and Q9/virial
near-wall behavior.

## Run

From the repository root:

```bash
bash scripts/run_periodic_cylinder_dynamic_visual_0105.sh
```

Shorter development run:

```bash
CASE_STEPS=1000 SUMMARY_EVERY=25 DUMP_STATE_EVERY=50 \
  bash scripts/run_periodic_cylinder_dynamic_visual_0105.sh
```

More economical visual output:

```bash
CASE_STEPS=3000 SUMMARY_EVERY=50 DUMP_STATE_EVERY=200 VISUAL_MAX_FRAMES=8 \
  bash scripts/run_periodic_cylinder_dynamic_visual_0105.sh
```

Disable automatic MATLAB report generation:

```bash
MAKE_VISUAL_REPORT=0 bash scripts/run_periodic_cylinder_dynamic_visual_0105.sh
```

## MATLAB report

The report writes PNG contact sheets under each run directory:

```text
runs/periodic_cylinder_q9_dynamic_visual_96x48_0105/visual_0105/
runs/periodic_cylinder_q9_virial_dynamic_visual_96x48_0105/visual_0105/
```

Default fields:

```text
N
speed
speedFluidActive
omega
q9CorrectionLimiterRatio
q9LowMassSuppressed
q9SafetyActive
q9ImmersedSolidAdjacentActive
q9ImmersedSolidCut
```

For each field, both a global view and a cylinder zoom are generated.  The
masked `speedFluidActive` view hides cells that are not marked active by the
Q9 immersed-solid sidecar, while the raw `speed` view remains available so that
post-processing does not hide possible artifacts.

Manual MATLAB call:

```matlab
report = make_periodic_cylinder_dynamic_visual_report_0105( ...
    {'../runs/periodic_cylinder_q9_dynamic_visual_96x48_0105', ...
     '../runs/periodic_cylinder_q9_virial_dynamic_visual_96x48_0105'}, ...
    'maxFrames', 10, ...
    'sampleMode', 'uniform', ...
    'zoomHalfWidth', 0.32, ...
    'zoomHalfHeight', 0.24, ...
    'visible', true);
```

## Acceptance checks

The expected numerical checks are:

```text
q9ImmersedHaloExcludedCells = 0
q9ImmersedSolidLeakMassFluxRms = 0
q9ImmersedSolidLeakMassFluxMaxAbs = 0
q6ImmersedSolidLeakProjectedFluxRms = 0
q9LowMassSuppressedCells should remain zero or isolated
q9VelocityLimitedCells should remain zero or small
totalMass should remain constant
kBTEstimate should stay stable
```

Visual checks:

```text
no inactive halo around the cylinder
no persistent Q9 low-mass mask around the cylinder
no persistent limiter ring around the cylinder
no artificial density accumulation at the solid boundary
speed/omega structures should grow smoothly from the body forcing
```
