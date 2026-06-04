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

## Completed hard-wall calibration results

The completed 30000-step hard-wall calibration confirms the corrected semantics:
all selected cases keep zero projected leak through the immersed solid, including
`q6ProjectionStrength = 0.50`.

| case | Q6 leak RMS | Q9 leak RMS | Q6 div after | P05(N) rev/ref | N<5 rev | CV(N) rev | omega low-k | largest rev. comp. | rev. comps |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Q6 s=0.50 | 0 | 0 | 4.214e-1 | 0.582 | 0.0119 | 0.119 | 0.135 | 0.202 | 29 |
| Q6 s=1.00 | 0 | 0 | 7.55e-10 | 0.710 | 0 | 0.105 | 0.188 | 0.211 | 24 |
| Q9 s=0.50 beta=1e-3 k=2 | 0 | 0 | 4.215e-1 | 0.730 | 0.0127 | 0.118 | 0.155 | 0.266 | 34 |
| Q9 s=0.50 beta=1e-3 k=4 | 0 | 0 | 4.205e-1 | 0.762 | 0 | 0.103 | 0.141 | 0.247 | 32 |

The result shifts the preferred no-virial baseline slightly toward the `lowK=4`
Q9 case.  `lowK=2` keeps the largest reversed component marginally larger, but
`lowK=4` gives the cleaner recirculation population low tail.  Since the current
validation argument is that quasi-incompressible SRC/MPCD should preserve
statistical reliability in recirculation zones, `lowK=4` is the better candidate
to test with the virial closure.

The final follow-up is documented in
`docs/BACKWARD_STEP_FINAL_Q9_VIRIAL_CONFIGURATION.md` and launched with:

```bash
./scripts/run_backward_step_final_liquid_config_test.sh
```

## Result artifacts

The calibration CSV and figures used for this documentation are committed in:

```text
docs/results/backward_step_final/backward_step_hardwall_calibration_summary.csv
docs/results/backward_step_final/backward_step_hardwall_calibration_key_metrics.png
docs/results/backward_step_final/backward_step_hardwall_calibration_projection_metrics.png
```

The final no-virial choice from this calibration is:

```text
Q9 hard-wall, q6ProjectionStrength=0.50, beta=0.001, lowK=4
```

The final liquid-closure extension of this baseline is documented in
`docs/BACKWARD_STEP_FINAL_LIQUID_CLOSURE_DEFAULT.md`.
