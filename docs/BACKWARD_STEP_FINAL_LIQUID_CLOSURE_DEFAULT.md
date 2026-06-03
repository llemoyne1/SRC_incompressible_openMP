# Backward-step final liquid-closure default

This note freezes the current default configuration for immersed-solid
quasi-incompressible SRC/MPCD after the backward-step calibration campaign.

The validation case is a periodic-x forced channel with an immersed rectangular
step. It is not yet an inlet/outlet backward-facing-step benchmark. Its purpose
is to stress the method in a separated flow with an internal hard wall and to
measure whether reconstructed fields remain statistically reliable in the
recirculation zone.

## Recommended default

```text
method = q9_virial
projectionImmersedSolidMaskEnable = true
projectionAllowUnmaskedImmersedSolid = false

q6ProjectionStrength = 0.50

q9MassFluxProjectionEnable = true
q9MassFluxProjectionStrength = 1.00
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

## Why this default was selected

The initial parameter sweep showed that classic SRC/MPCD has higher apparent
vorticity downstream of the step, but that a large part of the reversed region is
severely under-populated. The Q6/Q9 variants reduce high-frequency vorticity,
but produce better-supported, more spatially organized fields.

The hard-wall calibration then fixed the semantics of `q6ProjectionStrength`: an
under-relaxed interior Q6 correction no longer under-relaxes the impermeability
of immersed-solid faces. After this correction, all selected Q6/Q9 hard-wall
cases have zero projected leak through the immersed solid.

The final comparison between `Q9 lowK=4` and `Q9 lowK=4 + virial` shows that the
virial EOS closure improves population reliability substantially while leaving
the main recirculation/vorticity indicators almost unchanged.

## Hard-wall calibration summary

| case | Q6 leak RMS | Q9 leak RMS | Q6 div after | P05(N) rev/ref | N<5 rev | CV(N) rev | omega low-k | largest rev. comp. | rev. comps |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Q6 s=0.50 | 0 | 0 | 4.214e-1 | 0.582 | 0.0119 | 0.119 | 0.135 | 0.202 | 29 |
| Q6 s=1.00 | 0 | 0 | 7.55e-10 | 0.710 | 0 | 0.105 | 0.188 | 0.211 | 24 |
| Q9 s=0.50 beta=1e-3 k=2 | 0 | 0 | 4.215e-1 | 0.730 | 0.0127 | 0.118 | 0.155 | 0.266 | 34 |
| Q9 s=0.50 beta=1e-3 k=4 | 0 | 0 | 4.205e-1 | 0.762 | 0 | 0.103 | 0.141 | 0.247 | 32 |

The no-virial baseline selected for final testing is therefore:

```text
Q9 hard-wall, q6ProjectionStrength=0.50, beta=0.001, lowK=4
```

This choice weights population reliability above the largest reversed-component
score alone. The `lowK=2` case gives a slightly larger reversed component, but
`lowK=4` has a cleaner lower population tail in the reversed region.

## Final Q9 versus Q9 + virial result

| metric | Q9 k=4 | Q9 k=4 + virial | interpretation |
|---|---:|---:|---|
| Q6 leak RMS | 0 | 0 | immersed wall remains impermeable |
| Q9 leak RMS | 0 | 0 | mass-flux projection respects solid |
| Q6 div after | 4.205e-1 | 4.181e-1 | expected residual from `q6ProjectionStrength=0.50` |
| `stdNLate` | 7.675 | 7.380 | virial reduces population spread |
| `populationCvFluid` | 0.0736 | 0.0461 | strong global population regularization |
| `populationP05FluidOverReference` | 0.901 | 0.936 | improved low-tail population |
| `populationCvDownstream` | 0.0803 | 0.0501 | improved downstream reliability |
| `populationP05DownstreamOverReference` | 0.882 | 0.924 | improved downstream low tail |
| `populationP05ReversedOverReference` | 0.762 | 0.828 | improved recirculation low tail |
| `populationBelow5FractionReversed` | 0 | 0 | no under-sampled reversed cells |
| `populationTemporalCvMeanReversed` | 0.103 | 0.0929 | improved temporal reliability |
| `omegaRmsDownstream` | 0.0790 | 0.0792 | vorticity amplitude preserved |
| `omegaTotalRmsDownstream` | 0.389 | 0.385 | total vorticity essentially unchanged |
| `omegaMeanLowKFractionDownstream` | 0.141 | 0.147 | large-scale vorticity preserved/slightly improved |
| `reversedLargestComponentFraction` | 0.247 | 0.240 | comparable compact reversed component |
| `reversedComponentCount` | 32 | 37 | slightly more fragmentation with virial |
| `virialDuOverThermalRmsLate` | 0 | 0.00332 | virial kick is much smaller than thermal scale |

The slight increase in `reversedComponentCount` should be documented, but it is
not considered disqualifying because the population statistics improve strongly
and the main vorticity indicators remain essentially unchanged.

## Result artifacts

The committed result artifacts are stored under:

```text
docs/results/backward_step_final/
```

Important files:

```text
backward_step_hardwall_calibration_summary.csv
backward_step_final_liquid_config_summary.csv
backward_step_hardwall_calibration_key_metrics.png
backward_step_hardwall_calibration_projection_metrics.png
backward_step_final_liquid_config_reliability_structure.png
backward_step_final_liquid_config_projection_virial.png
```

Key figures:

![Hard-wall calibration key metrics](results/backward_step_final/backward_step_hardwall_calibration_key_metrics.png)

![Hard-wall calibration projection metrics](results/backward_step_final/backward_step_hardwall_calibration_projection_metrics.png)

![Final Q9/virial reliability and structure](results/backward_step_final/backward_step_final_liquid_config_reliability_structure.png)

![Final Q9/virial projection and virial diagnostics](results/backward_step_final/backward_step_final_liquid_config_projection_virial.png)

## Final interpretation

The selected Q9/virial configuration is the best current default for immersed
separated flows because it satisfies the hard numerical constraints and improves
the statistical reliability of reconstructed fields without replacing the flow
with an artificial pressure-driven dynamics. The virial kick remains very small
relative to the thermal velocity scale, while the low-population tail in the
recirculation zone improves from `P05/ref = 0.762` to `0.828`.

This configuration should now be rechecked on an independent immersed-cylinder
or von-Karman case before external inlet/outlet boundary conditions are added.
