# 0066b — tuned Q9 safety sweep for backward-step open boundaries

This patch is an incremental follow-up to 0066.  The first 0066 smoke showed
that the new Q9 guards prevent the catastrophic blow-up observed on the first
backward-step attempt, but it also showed that the default guarded Q9 setting
was still too aggressive: temperature rose to roughly twice the target and too
many cells were saved by the velocity limiter.

0066b therefore changes the validation script and analysis only.  It does not
change the Q6/Q9/virial kernels or the validated open-channel defaults from
0065b.  The softer Q9 settings are local to the backward-step immersed-solid
open-boundary smoke.

## Why this does not replace previous optima

The previous useful liquid/open-channel defaults remain the reference for cases
without an immersed solid:

```kv
q6ProjectionStrength = 0.50
q9MassFluxProjectionStrength = 1.00
q9DensityRelaxationBeta = 0.001
q9LowKMaxIndex = 4
q9EllipticLowPassPasses = 1
virialK = 0.50
virialBeta = 0.05
```

The new softer values are a **local safety regime** for the harder combination:

```text
inlet/outlet + fixed immersed rectangle + Q9 mass-flux correction
```

This combination contains reservoir strips, masked/cut faces and low-population
cells.  The Q9 correction must therefore be damped and excluded near critical
zones until the mass-flux boundary treatment is more mature.

## Default 0066b cases

The script now runs:

```text
backstep_q6_keepmean_s050
backstep_q9_safe_soft_s010_lim005_h4_e4
backstep_q9_safe_medium_s025_lim010_h3_e3
backstep_q9_virial_safe_soft_s010_lim005_h4_e4
```

The soft Q9 setting is:

```kv
q9MassFluxProjectionStrength = 0.10
q9DensityRelaxationBeta = 0.001
q9OpenBoundaryExclusionCells = 4
q9ImmersedSolidHaloCells = 4
q9MinCellMassForCorrection = 6.0
q9CorrectionVelocityLimiter = 0.005
```

For `kBT=0.0025`, `sqrt(kBT)=0.05`, so the soft limiter corresponds to about
10% of the thermal velocity scale.  The medium case keeps the first 0066 values
for comparison:

```kv
q9MassFluxProjectionStrength = 0.25
q9OpenBoundaryExclusionCells = 3
q9ImmersedSolidHaloCells = 3
q9CorrectionVelocityLimiter = 0.01
```

## New analysis fields

`analyze_backward_step_q9_safety_smoke_0066.m` now reports:

```text
q9VelocityLimitedFractionFinal
passSolverConvergence
passBoundedSafety
passTunedQ9Target
status
```

The statuses distinguish strict solver convergence from bounded physical
behaviour.  A case can be bounded even if the masked/open elliptic CG solve does
not report strict convergence, provided the correction remains effective and the
run does not heat or blow up.

Default physical targets:

```text
kBTMeanLate / kBTTarget <= 1.5
q9VelocityLimitedCells / q9SafetyActiveCells <= 0.10
q9MassDivRatioFinal < 1.02
virialDuOverThermalRms < 0.05
```

## Run

```bash
chmod +x scripts/run_backward_step_q9_safety_smoke_0066.sh
CASE_STEPS=1000 ./scripts/run_backward_step_q9_safety_smoke_0066.sh
```

Shorter tuning run:

```bash
RUN_MEDIUM_Q9=0 RUN_SOFT_VIRIAL=0 CASE_STEPS=500 \
  ./scripts/run_backward_step_q9_safety_smoke_0066.sh
```

Analyze:

```matlab
cd matlab
S = analyze_backward_step_q9_safety_smoke_0066('root','..');
cd ..
```
