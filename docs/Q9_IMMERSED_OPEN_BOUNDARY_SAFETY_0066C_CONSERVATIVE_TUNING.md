# 0066c — conservative Q9 tuning for backward-step open boundaries

This patch is an incremental follow-up to 0066/0066b.  The first guarded Q9
patch removed the catastrophic blow-up, and 0066b showed that the softer setting
reduced the temperature rise and the raw correction amplitude.  However, the Q9
limiter was still active in about 19% of the Q9-active cells and the late
kinetic temperature remained slightly above the target bound.

0066c therefore keeps the same C++ safety kernel and changes only the tuning
script and MATLAB analysis.  The goal is to test a more conservative immersed
solid/open-boundary Q9 regime before considering this configuration for
validation.

## Scope

This patch does **not** change the validated open-channel defaults from 0065b:

```kv
q6ProjectionStrength = 0.50
q9MassFluxProjectionStrength = 1.00
q9DensityRelaxationBeta = 0.001
q9LowKMaxIndex = 4
q9EllipticLowPassPasses = 1
virialK = 0.50
virialBeta = 0.05
```

The conservative values below are only for the difficult combination:

```text
inlet/outlet + fixed immersed rectangle + Q9 mass-flux correction
```

In this configuration, Q9 sees reservoir strips, masked cells, cut/closed faces
and low-population cells.  The conservative setting is therefore a local safety
regime, not a replacement for the clean open-channel optimum.

## Default 0066c cases

The script now runs three cases by default:

```text
backstep_q6_keepmean_s050
backstep_q9_safe_vsoft_s005_lim003_h5_e5_m8
backstep_q9_virial_safe_vsoft_s005_lim003_h5_e5_m8
```

The very-soft Q9 setting is:

```kv
q9MassFluxProjectionStrength = 0.05
q9DensityRelaxationBeta = 0.001
q9OpenBoundaryExclusionCells = 5
q9ImmersedSolidHaloCells = 5
q9MinCellMassForCorrection = 8.0
q9CorrectionVelocityLimiter = 0.003
```

For `kBT=0.0025`, `sqrt(kBT)=0.05`, so the limiter is about 6% of the thermal
velocity scale.  This is intentionally conservative: the aim is not to obtain a
strong Q9 effect yet, but to determine whether Q9 can be made bounded and mostly
unlimited near an immersed step in an open domain.

An extra ultra-conservative case can be enabled with:

```bash
RUN_ULTRA_Q9=1 ./scripts/run_backward_step_q9_safety_smoke_0066.sh
```

It uses the same strength and exclusions but a limiter of `0.0025`.

The previous 0066b soft/medium cases can still be reproduced when needed:

```bash
RUN_0066B_SOFT=1 RUN_0066B_MEDIUM=1 \
  ./scripts/run_backward_step_q9_safety_smoke_0066.sh
```

## Updated analysis criteria

The analysis now reports the Q9 temperature increase relative to the Q6
reference:

```text
q9KBTOverQ6Late
passRelativeThermal
```

This is important because the backward-step Q6 reference already heats above the
nominal target due to keep-mean forcing, walls and the immersed rectangle.
Absolute temperature is still tracked, but the relevant question for Q9 tuning is
whether Q9 adds excessive heating relative to Q6.

Default targets:

```text
kBTMeanLate / kBTTarget <= 1.50
q9KBTOverQ6Late <= 1.15
q9VelocityLimitedCells / q9SafetyActiveCells <= 0.12
q9MassDivRatioFinal < 1.02
virialDuOverThermalRms < 0.05
```

## Run

```bash
chmod +x scripts/run_backward_step_q9_safety_smoke_0066.sh
CASE_STEPS=1000 ./scripts/run_backward_step_q9_safety_smoke_0066.sh
```

Optional quick comparison with the previous 0066b soft case:

```bash
RUN_0066B_SOFT=1 RUN_SOFT_VIRIAL=0 CASE_STEPS=1000 \
  ./scripts/run_backward_step_q9_safety_smoke_0066.sh
```

Analyze:

```matlab
cd matlab
S = analyze_backward_step_q9_safety_smoke_0066('root','..');
cd ..
```
