# Backward-step masked Q6/Q9 structure suite

This suite compares the periodic-x forced rectangular-step case in three modes:

- classic SRC/MPCD;
- Q6 velocity projection with an immersed-solid mask;
- Q9 filtered mass-flux projection with the same immersed-solid mask.

It is **not** yet a canonical inlet/outlet backward-facing-step benchmark.  The
external `x` boundaries remain periodic and the flow is driven by a body
acceleration.  The purpose is narrower: quantify whether masked Q6/Q9 preserve a
separated/reversed region around the immersed rectangle while preventing the
elliptic correction from crossing the solid.

## Files

```text
examples/params_backward_step_classic_structure_96x48.kv
examples/params_backward_step_q6_mask_structure_96x48.kv
examples/params_backward_step_q9_mask_structure_96x48.kv
scripts/run_backward_step_masked_structure_suite.sh
matlab/validate_backward_step_masked_structure_suite.m
```

The Q6/Q9 cases use the same geometry and forcing as the high-signal classic
structure case:

```text
bodyAccelerationX = 0.015
kBT = 0.0025
immersedSolidShape = rectangle
immersedSolidXMin = 0.25
immersedSolidXMax = 0.65
immersedSolidYMin = 0.0
immersedSolidYMax = 0.50
projectionImmersedSolidMaskEnable = true
```

The classic, Q6 and Q9 structure cases use the same physical duration by
default (`nSteps = 30000`).  This makes the late-window averages directly
comparable.  If turnaround time is a concern, shorten all three cases together
or compare only over a common truncated time window.

## Run

From the repository root:

```bash
./scripts/run_backward_step_masked_structure_suite.sh
```

To skip the classic rerun when `runs/backward_step_classic_structure_96x48`
already exists:

```bash
RUN_CLASSIC=0 ./scripts/run_backward_step_masked_structure_suite.sh
```

To run only Q6 or only Q9:

```bash
RUN_CLASSIC=0 RUN_Q9=0 ./scripts/run_backward_step_masked_structure_suite.sh
RUN_CLASSIC=0 RUN_Q6=0 ./scripts/run_backward_step_masked_structure_suite.sh
```

To run MATLAB post-processing automatically after the simulations:

```bash
RUN_ANALYSIS=1 ./scripts/run_backward_step_masked_structure_suite.sh
```

## MATLAB analysis

From the repository root:

```matlab
cd matlab
suite = validate_backward_step_masked_structure_suite();
```

If only Q6/Q9 were run:

```matlab
suite = validate_backward_step_masked_structure_suite('runDirs', { ...
    '../runs/backward_step_q6_mask_structure_96x48', ...
    '../runs/backward_step_q9_mask_structure_96x48'});
```

The validator writes:

```text
runs/backward_step_masked_structure_suite_analysis/backward_step_masked_structure_suite_summary.csv
runs/backward_step_masked_structure_suite_analysis/backward_step_masked_structure_suite_lower_profiles.csv
runs/backward_step_masked_structure_suite_analysis/backward_step_masked_structure_suite_fields.png
runs/backward_step_masked_structure_suite_analysis/backward_step_masked_structure_suite_profiles.png
```

## Quantities to inspect

For geometric correctness:

```text
maxParticlesInsideRectangle = 0
q6ImmersedSolidLeakProjectedFluxRmsLate ~= 0 only for invalid runs; expected 0
q9ImmersedSolidLeakMassFluxRmsLate      ~= 0 only for invalid runs; expected 0
```

For numerical behavior:

```text
q6ConvergedFractionLate
q6DivAfterProjectedFluxRmsLate
q6CorrectionVelocityMaxAbsLate
q9ConvergedFractionLate
q9MassFluxDivAfterRmsLate
q9DensityStdRatioEstimateLate
q9CorrectionVelocityMaxAbsLate
```

For flow-structure comparison:

```text
reversedUxFraction
omegaRmsDownstream
reattachmentLengthProfile
meanUxDownstreamOverThermal
```

The expected behavior is not that Q6/Q9 reproduce the classic result exactly.
Q6 changes the velocity field by enforcing a projected incompressible-like
constraint; Q9 additionally changes the low-k mass-flux dynamics.  The important
checks are that the corrections remain bounded, do not cross the immersed solid,
and do not erase the separated/reversed region entirely.
