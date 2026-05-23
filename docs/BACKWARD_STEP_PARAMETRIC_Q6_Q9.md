# Backward-step immersed solid: masked Q6/Q9 parametric suite

This suite tunes the masked Q6/Q9 projection strength on the immersed-rectangle
step before inlet/outlet boundary conditions are introduced.

The case remains a periodic-x forced channel with a bottom-attached immersed
rectangle. It is not yet a canonical backward-facing-step benchmark.

## Why this suite exists

The first long masked runs showed that full Q6 projection is numerically clean
and respects the immersed-solid mask, but it strongly damps the downstream
vorticity and the reversed-flow signal. Q9 was stable and leak-free but, with the
initial filtered settings, it only weakly affected the density scatter.

This suite therefore adds two controls:

- `q6ProjectionStrength`, an under-relaxation factor for the Q6 velocity
  correction. `1.0` is the previous full projection. `0.0` leaves Q6 inactive
  after solving the elliptic problem.
- runtime-generated Q9 parameter cases that combine a selected Q6 strength with
  several density-relaxation/filter settings.

## Run

From the repository root:

```bash
./scripts/build_src_mpcd_base.sh
./scripts/run_backward_step_parametric_suite.sh
```

Default cases:

```text
classic
Q6 q6ProjectionStrength = 0.25
Q6 q6ProjectionStrength = 0.50
Q6 q6ProjectionStrength = 0.75
Q6 q6ProjectionStrength = 1.00
Q9 q6ProjectionStrength = 0.50, beta = 0.00025, lowK = 2
Q9 q6ProjectionStrength = 0.50, beta = 0.00100, lowK = 2
Q9 q6ProjectionStrength = 0.50, beta = 0.00400, lowK = 2
Q9 q6ProjectionStrength = 0.50, beta = 0.00100, lowK = 4
```

The script writes generated parameter files to:

```text
runs/backward_step_parametric_suite_configs/
```

and run outputs to:

```text
runs/backward_step_parametric_*/
```

Useful environment overrides:

```bash
N_STEPS=15000 ./scripts/run_backward_step_parametric_suite.sh
RUN_CLASSIC=0 ./scripts/run_backward_step_parametric_suite.sh
RUN_Q9_SWEEP=0 ./scripts/run_backward_step_parametric_suite.sh
Q6_STRENGTHS="0.10 0.25 0.50" ./scripts/run_backward_step_parametric_suite.sh
Q9_CASES="0.50:0.00100:2 0.75:0.00100:2" ./scripts/run_backward_step_parametric_suite.sh
```

## MATLAB analysis

From the repository root:

```matlab
cd matlab
suite = validate_backward_step_parametric_suite();
```

or directly after the runs:

```bash
RUN_ANALYSIS=1 ./scripts/run_backward_step_parametric_suite.sh
```

Outputs are written to:

```text
runs/backward_step_parametric_suite_analysis/
```

Main files:

```text
backward_step_parametric_suite_summary.csv
backward_step_parametric_suite_scalar_metrics.png
backward_step_parametric_suite_q9_metrics.png
backward_step_masked_structure_suite_fields.png
backward_step_masked_structure_suite_profiles.png
```

## Diagnostics to inspect

For the mask:

```text
maxParticlesInsideRectangle = 0
q6ImmersedSolidLeakProjectedFluxRmsLate = 0
q9ImmersedSolidLeakMassFluxRmsLate = 0
```

For the Q6 strength sweep:

```text
omegaRmsDownstream
reversedUxFraction
meanUxDownstreamOverThermal
q6DivAfterProjectedFluxRmsLate
q6CorrectionVelocityRmsLate
```

For Q9 tuning:

```text
q9DensityStdRatioEstimateLate
q9CorrectionVelocityRmsLate
q9TargetDivergenceFilterRatioLate
omegaRmsDownstream
```

The intended outcome is not to find a universal parameter value. The objective is
to determine whether a partial Q6 correction preserves more separated structure
while retaining most of the incompressibility benefit, and whether Q9 needs a
larger relaxation/filter bandwidth to have a measurable density effect on this
immersed-step case.

## Population reliability diagnostics

After applying the population-reliability diagnostics patch, the parametric
analysis also writes

```text
runs/backward_step_parametric_suite_analysis/backward_step_parametric_suite_population_metrics.png
```

and the summary table contains downstream and reversed-region population-tail
metrics. These are part of the method-selection criterion: a good Q6/Q9 setting
should not only reduce compressibility diagnostics, but should also preserve
organized recirculation in cells whose particle population remains statistically
credible.
