# 0100 — Short immersed-circle face/cell-mask smoke suite

This note documents the short validation launcher added after the Q9 immersed-solid
face/cell mask and virial normal-kick clipping patches.

The objective is deliberately modest: detect runtime, masking, sidecar, and
summary-counter regressions quickly. This is not a calibrated wake or transport
validation.

## Added files

```text
examples/params_immersed_circle_classic_mask_smoke_48x48_0100.kv
examples/params_immersed_circle_q6_mask_smoke_48x48_0100.kv
examples/params_immersed_circle_q9_mask_smoke_48x48_0100.kv
examples/params_immersed_circle_q9_virial_mask_smoke_48x48_0100.kv
scripts/run_immersed_circle_face_cell_smoke_0100.sh
matlab/analyze_immersed_circle_face_cell_smoke_0100.m
doc/README_0100_IMMERSED_CIRCLE_FACE_CELL_SMOKE.md
```

## Default case

The suite uses a small periodic box with one analytic circular immersed solid:

```text
Lx = Ly = 1
Nx = Ny = 48
gamma = 20
circle center = (0.5, 0.5)
circle radius = 0.12
nSteps = 150
summaryEvery = 25
dumpStateEvery = 25
```

The state file is generated once as:

```text
initial_state_immersed_circle_48x48_g20_0100.smpcd
```

The initial generator excludes particles from the analytic circle. The C++ run
then uses `immersedSolidShape = circle` and the face/cell immersed-solid mask.

## How to run

From the repository root:

```bash
bash scripts/run_immersed_circle_face_cell_smoke_0100.sh
```

Defaults:

```text
RUN_CLASSIC=0
RUN_Q6=1
RUN_Q9=1
RUN_Q9_VIRIAL=1
CASE_STEPS=150
SUMMARY_EVERY=25
DUMP_STATE_EVERY=25
NUM_THREADS=4
CLEAN_OUTPUTS=1
RUN_MATLAB_REPORT=0
```

Examples:

```bash
# Fastest Q9-only check
RUN_Q6=0 RUN_Q9=1 RUN_Q9_VIRIAL=0 CASE_STEPS=75 \
  bash scripts/run_immersed_circle_face_cell_smoke_0100.sh

# Include classic reference as well
RUN_CLASSIC=1 bash scripts/run_immersed_circle_face_cell_smoke_0100.sh

# Generate MATLAB compact report after the C++ runs
RUN_MATLAB_REPORT=1 bash scripts/run_immersed_circle_face_cell_smoke_0100.sh
```

## Output directories

```text
runs/immersed_circle_classic_mask_smoke_48x48_0100
runs/immersed_circle_q6_mask_smoke_48x48_0100
runs/immersed_circle_q9_mask_smoke_48x48_0100
runs/immersed_circle_q9_virial_mask_smoke_48x48_0100
```

The Q9 and Q9+virial cases enable binary Q9 diagnostic sidecars. The Q6 and
classic cases are not expected to produce `.q9bin` files.

## Minimal acceptance checks

The launcher prints selected final counters after each run. For the Q9 and
Q9+virial cases, the important checks are:

```text
q9ImmersedHaloExcludedCells = 0
q9ImmersedSolidActiveAdjacentCells > 0
q9ImmersedSolidActiveCutCells > 0
q9ImmersedSolidClosedXFaces/YFaces > 0
q9ImmersedSolidLeakMassFluxRms is near machine noise
q9bin_count > 0
```

For the Q9+virial case, the normal clipping counters should be present:

```text
virialImmersedSolidActiveAdjacentCells > 0
virialImmersedSolidNormalKickClippedCells present
virialImmersedSolidNormalKickClippedComponents present
virialImmersedSolidNormalKickClippedRms present
virialImmersedSolidNormalKickClippedMaxAbs present
```

The clipping counters may be small or even zero for very short or weakly forced
runs if the local virial kick does not point into the solid. Their presence is
the key smoke-test condition.

## MATLAB compact report

After the run, from `matlab/`:

```matlab
T = analyze_immersed_circle_face_cell_smoke_0100();
```

The function writes, by default:

```text
runs/immersed_circle_face_cell_smoke_0100_summary.csv
```

It reports final Q6/Q9/virial immersed-solid counters, sidecar counts, frame
counts, and the maximum number of particles found inside the analytic circle in
dumped states.

## Scope limitations

This suite is intentionally short and cheap. It should not be interpreted as:

- a wake-shedding validation;
- a viscosity/transport calibration;
- a final von Karman benchmark;
- an inlet/outlet immersed-solid validation.

It is a development guardrail before moving to longer cylinder/channel and
open-boundary obstacle cases.
