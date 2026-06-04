# Backward step final Q9/virial configuration test

This note records the current immersed-step calibration status and defines the
last focused test needed before freezing a default immersed-solid liquid-closure
configuration.

The case remains a periodic-x forced channel with an immersed rectangular step.
It is a separated-flow stress test for the method, not yet a true inlet/outlet
backward-facing-step benchmark.


## Final lowK=4 Q9/Q9+virial test completed

The focused final test has now been completed. The recommended immersed-solid
liquid-closure default is confirmed as:

```text
method = q9_virial
projectionImmersedSolidMaskEnable = true
q6ProjectionStrength = 0.50
q9MassFluxProjectionStrength = 1.00
q9DensityRelaxationBeta = 0.00100
q9LowKMaxIndex = 4
q9EllipticLowPassPasses = 1
Kvirial = 0.50
virialBeta = 0.05
```

The final comparison is:

| metric | Q9 k=4 | Q9 k=4 + virial | conclusion |
|---|---:|---:|---|
| Q6 leak RMS | 0 | 0 | hard-wall condition preserved |
| Q9 leak RMS | 0 | 0 | mass-flux projection respects solid |
| Q6 div after | 4.205e-1 | 4.181e-1 | expected residual for `q6ProjectionStrength=0.50` |
| std(N) late | 7.675 | 7.380 | improved by virial |
| population CV, fluid | 0.0736 | 0.0461 | improved by virial |
| P05(N) fluid/ref | 0.901 | 0.936 | improved low tail |
| P05(N) reversed/ref | 0.762 | 0.828 | improved recirculation reliability |
| N<5 reversed | 0 | 0 | no under-sampled reversed cells |
| population temporal CV reversed | 0.103 | 0.0929 | improved by virial |
| omega RMS downstream | 0.0790 | 0.0792 | preserved |
| omega total RMS downstream | 0.389 | 0.385 | preserved |
| omega low-k fraction | 0.141 | 0.147 | preserved/slightly improved |
| largest reversed component | 0.247 | 0.240 | comparable |
| reversed component count | 32 | 37 | slightly more fragmented |
| virial du / u_th RMS | 0 | 0.00332 | very small kick |

The virial closure therefore improves the population reliability of the
recirculation zone without significantly changing the principal vorticity
metrics. The only small caveat is a modest increase in the number of reversed
components; this is not considered disqualifying because the population
statistics and large-scale vorticity remain favorable.

Committed result artifacts are available in:

```text
docs/results/backward_step_final/
```

See also `docs/BACKWARD_STEP_FINAL_LIQUID_CLOSURE_DEFAULT.md` for the concise
configuration freeze note.

## Result of the hard-wall calibration

After the hard-wall projection fix, `q6ProjectionStrength < 1` no longer makes
immersed-solid faces partially permeable. The solid constraint remains hard,
while only the interior fluid-fluid Q6 correction is under-relaxed.

The second-stage calibration gave the following representative late-window
results:

| case | Q6 leak RMS | Q9 leak RMS | Q6 div after | P05(N) rev/ref | N<5 rev | CV(N) rev | omega low-k | largest rev. comp. | rev. comps |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Q6 s=0.50 | 0 | 0 | 4.214e-1 | 0.582 | 0.0119 | 0.119 | 0.135 | 0.202 | 29 |
| Q6 s=1.00 | 0 | 0 | 7.55e-10 | 0.710 | 0 | 0.105 | 0.188 | 0.211 | 24 |
| Q9 s=0.50 beta=1e-3 k=2 | 0 | 0 | 4.215e-1 | 0.730 | 0.0127 | 0.118 | 0.155 | 0.266 | 34 |
| Q9 s=0.50 beta=1e-3 k=4 | 0 | 0 | 4.205e-1 | 0.762 | 0 | 0.103 | 0.141 | 0.247 | 32 |

The `lowK=2` Q9 case keeps a slightly more compact largest reversed component,
whereas the `lowK=4` Q9 case has a cleaner population low tail in the reversed
region. Since the current validation argument emphasizes statistical reliability
of reconstructed fields in recirculation zones, the selected no-virial baseline
is:

```text
q6ProjectionStrength = 0.50
q9DensityRelaxationBeta = 0.00100
q9LowKMaxIndex = 4
projectionImmersedSolidMaskEnable = true
virialKickEnable = false
```

This setting is the best current compromise for an immersed separated flow when
population reliability is weighted above preserving the largest-component score
alone.

## Virial comparison already completed at lowK=2

The first Q9/Q9+virial comparison used the same Q6/Q9 settings but with
`q9LowKMaxIndex = 2`. It showed the expected role of the virial closure: the
virial kick improves the population reliability without becoming the dominant
dynamics.

| case | P05(N) rev/ref | N<5 rev | CV(N) rev | omega low-k | largest rev. comp. | virial du/u_th |
|---|---:|---:|---:|---:|---:|---:|
| Q9 k=2, no virial | 0.656 | 0.0119 | 0.131 | 0.153 | 0.167 | 0 |
| Q9 k=2 + virial | 0.834 | 0 | 0.091 | 0.155 | 0.209 | 0.00332 |

The virial correction therefore looks like a density/population regularization
on this case, not like a new forcing mechanism: its velocity kick is far below
the thermal velocity scale and the large-scale vorticity indicators remain close
to the no-virial case.

## Reproducing the final focused test

The completed final direct comparison was:

```text
Q9 hard-wall lowK=4, no virial
Q9 hard-wall lowK=4, with virial
```

The no-virial run is normally already available from the hard-wall calibration
suite:

```text
runs/backward_step_hardwall_q9_s0p50_b0p00100_k4_96x48
```

The new final virial run is generated by:

```bash
./scripts/run_backward_step_final_liquid_config_test.sh
```

By default this script only runs the missing virial case:

```text
runs/backward_step_final_q9_k4_virial_96x48
```

To rerun both no-virial and virial cases in fresh directories:

```bash
RUN_BASELINE=1 ./scripts/run_backward_step_final_liquid_config_test.sh
```

For a short smoke test:

```bash
N_STEPS=5000 ./scripts/run_backward_step_final_liquid_config_test.sh
```

Analyze from the repository root with:

```matlab
cd matlab
suite = validate_backward_step_final_liquid_config();
```

The analysis writes:

```text
runs/backward_step_final_liquid_config_analysis/backward_step_final_liquid_config_summary.csv
runs/backward_step_final_liquid_config_analysis/backward_step_final_liquid_config_reliability_structure.png
runs/backward_step_final_liquid_config_analysis/backward_step_final_liquid_config_projection_virial.png
```

## Acceptance criteria for freezing the default

Mandatory numerical checks:

```text
maxParticlesInsideRectangle = 0
q6ConvergedFractionLate = 1
q9ConvergedFractionLate = 1
q6ImmersedSolidLeakProjectedFluxRmsLate = 0
q9ImmersedSolidLeakMassFluxRmsLate = 0
```

Population reliability checks in the reversed region:

```text
populationP05ReversedOverReference >= 0.75
populationBelow5FractionReversed = 0
populationTemporalCvMeanReversed <= 0.11
```

Virial safety checks:

```text
virialDuOverThermalRmsLate << 1
virialDuAppliedMaxAbsLate remains small compared with thermalVelocityLate
```

Structure checks:

```text
omegaMeanLowKFractionDownstream should not degrade strongly versus no virial
reversedLargestComponentFraction should remain comparable or improve
reversedComponentCount should not increase enough to indicate fragmentation
```

The final `lowK=4 + virial` run satisfies these checks. The recommended
immersed-solid liquid closure default is:

```text
method = q9_virial
projectionImmersedSolidMaskEnable = true
q6ProjectionStrength = 0.50
q9MassFluxProjectionEnable = true
q9MassFluxProjectionStrength = 1.0
q9DensityRelaxationBeta = 0.00100
q9TargetFilter = elliptic_lowpass
q9LowKMaxIndex = 4
q9EllipticLowPassPasses = 1
virialKickEnable = true
Kvirial = 0.50
virialBeta = 0.05
virialRhoEOSRefMode = current_uniform
virialRhoUniformMode = particle_mean
virialDriveTargetMode = current_uniform
virialRhoKickMode = uniform_now
virialMomentumCorrectionEnable = true
```

This default should then be rechecked on an independent geometry, preferably an
immersed cylinder/von-Karman case, before moving to inlet/outlet boundary
conditions.
