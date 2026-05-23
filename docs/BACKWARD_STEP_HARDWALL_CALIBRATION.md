# Backward step hard-wall Q6/Q9 calibration

This note documents the second-stage immersed-step calibration to be run
after the hard-wall projection fix.

The first parameter sweep showed that under-relaxing `q6ProjectionStrength`
was useful for preserving organized structures, but it also revealed a
semantic problem: when `q6ProjectionStrength < 1`, the immersed-solid
no-through-flux constraint was under-relaxed too. This made the obstacle
partially permeable in the projected field. The hard-wall fix changes the
semantics:

- open fluid-fluid faces use the requested `q6ProjectionStrength`;
- closed immersed-solid faces always receive the full no-flux correction;
- the solid leak diagnostics must therefore remain zero even when
  `q6ProjectionStrength = 0.50`.

This suite reruns only the candidates needed to calibrate the method after
that correction:

```text
Q6 s = 0.50 hard-wall
Q6 s = 1.00 hard-wall
Q9 s = 0.50, beta = 0.001, lowK = 2 hard-wall
Q9 s = 0.50, beta = 0.001, lowK = 4 hard-wall
```

The goal is to pick a default immersed-solid quasi-incompressible setting
before comparing Q6/Q9 to Q6/Q9/virial liquid closure.

## Run

From the repository root:

```bash
./scripts/run_backward_step_hardwall_calibration_suite.sh
```

Short smoke version:

```bash
N_STEPS=5000 ./scripts/run_backward_step_hardwall_calibration_suite.sh
```

Run only the currently favored Q9 low-k case:

```bash
RUN_Q6_S050=0 RUN_Q6_S100=0 RUN_Q9_K4=0 ./scripts/run_backward_step_hardwall_calibration_suite.sh
```

Run with MATLAB analysis at the end:

```bash
RUN_ANALYSIS=1 ./scripts/run_backward_step_hardwall_calibration_suite.sh
```

## Analyze

From the repository root:

```matlab
cd matlab
suite = validate_backward_step_hardwall_calibration_suite();
```

The analysis writes:

```text
runs/backward_step_hardwall_calibration_analysis/backward_step_hardwall_calibration_summary.csv
runs/backward_step_hardwall_calibration_analysis/backward_step_hardwall_calibration_key_metrics.png
runs/backward_step_hardwall_calibration_analysis/backward_step_hardwall_calibration_projection_metrics.png
```

It also reuses the existing masked-structure analysis outputs, including the
mean-field, coherence, and population-reliability figures.

## Selection criteria

The first mandatory checks are hard constraints:

```text
q6ImmersedSolidLeakProjectedFluxRmsLate = 0
q6ImmersedSolidLeakProjectedFluxMaxAbsLate = 0
q9ImmersedSolidLeakMassFluxRmsLate = 0
q9ImmersedSolidLeakMassFluxMaxAbsLate = 0
maxParticlesInsideRectangle = 0
```

Then select the best compromise using population reliability and organized
structure metrics, not `omegaRmsDownstream` alone:

```text
populationP05ReversedOverReference
populationLowHalfRefFractionReversed
populationBelow5FractionReversed
populationTemporalCvMeanReversed
omegaMeanLowKFractionDownstream
reversedLargestComponentFraction
reversedComponentCount
uxReversePersistenceMaxDownstream
```

A plausible target is the `Q9 s=0.50 beta=1e-3 lowK=2` case, provided the
hard-wall leak diagnostics remain zero after the fix. If `lowK=4` improves
population reliability without fragmenting the reversed region, it can be
kept as an alternative; otherwise `lowK=2` remains the cleaner default.
