# 0067c — Hard-inlet backward step with soft Q9 settings

This patch keeps the hard inlet reservoir introduced in 0067 and changes only the
validation runner/analysis for the backward-step case. The goal is to test Q9 in
its currently most plausible safe range for an open domain with an immersed
rectangle.

## Default cases

The runner now launches:

- `backstep_q6_hard_inlet`, the Q6 reference;
- `backstep_q9_hard_inlet_s003`, Q9 with `q9MassFluxProjectionStrength = 0.03`;
- `backstep_q9_hard_inlet_s005`, Q9 with `q9MassFluxProjectionStrength = 0.05`;
- `backstep_q9_virial_hard_inlet_s005`, Q9+virial with the same soft Q9 setting.

The previous strong `s=0.25` case is still available by setting
`RUN_Q9_STRONG_REFERENCE=1`, but it is no longer part of the default validation
because it was too dissipative/heating in the hard-inlet backward-step geometry.

## Q9 safety parameters

The default safeguards are:

```kv
q9OpenBoundaryExclusionCells = 5
q9ImmersedSolidHaloCells = 5
q9MinCellMassForCorrection = 8.0
q9CorrectionVelocityLimiter = 0.003
```

They can be overridden at launch time with:

```bash
Q9_OPEN_EXCLUSION_CELLS=5 \
Q9_IMMERSED_HALO_CELLS=5 \
Q9_MIN_CELL_MASS=8.0 \
Q9_CORRECTION_LIMITER=0.003 \
CASE_STEPS=1000 \
./scripts/run_backward_step_hard_inlet_validation_0067.sh
```

## Analysis additions

The MATLAB analysis now reports:

- raw and limited Q9 correction maxima;
- Q9 limiter value;
- active/excluded/limited safety-cell counts;
- limited-cell fraction;
- late Q9 temperature relative to the Q6 reference;
- pass/fail flags for hard-inlet density, limiter activity, limited fraction and
  Q9 thermal increment relative to Q6.

The main target for a usable compromise is:

```text
q9KBTOverQ6Late <= 1.15
q9VelocityLimitedFractionFinal <= 0.15
q9CorrectionVelocityMaxAbsFinal <= 1.05*q9CorrectionVelocityLimiterFinal
stdNFinal comparable to Q6
```
