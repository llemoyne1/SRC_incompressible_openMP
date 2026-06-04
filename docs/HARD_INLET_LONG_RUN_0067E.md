# 0067e — Backward-step hard-inlet long run

This run set is the first overnight/reference validation for the backward-step open-boundary case after hard inlet density control and Q9 safety diagnostics.

It launches exactly three cases:

1. `backstep_q6_hard_inlet_long`
2. `backstep_q9_hard_inlet_s003_long`
3. `backstep_q9_virial_hard_inlet_s003_long`

Default runtime parameters:

```text
CASE_STEPS=12000
SUMMARY_EVERY=200
DUMP_STATE_EVERY=2000
NUM_THREADS=8
RUN_ROOT=runs/backward_step_hard_inlet_long_0067e
```

The Q9 settings are deliberately soft and specific to backward-step + open boundary + immersed rectangle:

```text
q9MassFluxProjectionStrength = 0.03
q9DensityRelaxationBeta = 0.001
q9OpenBoundaryExclusionCells = 5
q9ImmersedSolidHaloCells = 5
q9MinCellMassForCorrection = 8.0
q9CorrectionVelocityLimiter = 0.003
```

Virial settings:

```text
virialK = 0.50
virialBeta = 0.05
virialOpenBoundaryExclusionCells = 5
```

Run:

```bash
chmod +x scripts/run_backward_step_hard_inlet_long_0067e.sh
./scripts/run_backward_step_hard_inlet_long_0067e.sh
```

Longer overnight run:

```bash
CASE_STEPS=20000 DUMP_STATE_EVERY=5000 NUM_THREADS=8 \
  ./scripts/run_backward_step_hard_inlet_long_0067e.sh
```

Analyze:

```matlab
cd matlab
S = analyze_backward_step_hard_inlet_validation_0067( ...
    'root','..', ...
    'runRoot','runs/backward_step_hard_inlet_long_0067e');
cd ..
```

Main criteria:

```text
inletReservoirStdNFinal = 0
q6ConvergedFinal = 1
q9ConvergedFinal = 1
q9KBTOverQ6Late <= 1.10--1.15
q9VelocityLimitedFractionFinal <= 0.10--0.15
q9CorrectionVelocityRmsFinal < 0.002
q9CorrectionVelocityMaxAbsFinal ≈ 0.003
virialMomentumResidualAfterFinal = 0
virialDuOverThermalRmsFinal < 0.01
```
