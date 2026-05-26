# 0070 — Q9 low-mass ramp/floor actually applied

This update wires the already parsed `q9LowMassTreatment = ramp_floor` parameters into the Q9 flux-to-velocity conversion.
It does not add any outlet sponge/cap and does not change the generic elliptic operator.

## Behaviour

Historical mode remains available:

```text
q9LowMassTreatment = suppress
```

In this mode, the previous hard cutoff is preserved:

```text
cellMass <= q9MinCellMassForCorrection  -> no Q9 kick in that cell
cellMass  > q9MinCellMassForCorrection  -> dU = dJ / cellMass
```

The new effective mode is:

```text
q9LowMassTreatment = ramp_floor
q9LowMassRampStart = 1.0
q9LowMassRampEnd = 8.0
q9MassFloorForCorrection = 8.0
```

In this mode:

```text
cellMass <= rampStart -> no Q9 kick
rampStart < cellMass < rampEnd -> dJ is multiplied by a linear ramp weight
cellMass < massFloor -> dU is computed with massFloor instead of cellMass
```

The applied correction flux diagnostic remains consistent with the actual velocity kick applied to particles:

```text
appliedCorrectionFlux = dU * realCellMass
```

## New runtime summary columns

The C++ runtime summary now distinguishes the low-mass mechanisms:

```text
q9LowMassSuppressedCells
q9LowMassRampedCells
q9MassFloorAppliedCells
q9VelocityLimitedCells
q9MassFloorForCorrection
q9LowMassRampStart
q9LowMassRampEnd
```

Interpretation:

```text
q9LowMassSuppressedCells  : inactive because cell mass is zero or <= rampStart in ramp_floor mode
q9LowMassRampedCells      : active, but correction flux is linearly reduced
q9MassFloorAppliedCells   : active, but dU uses max(cellMass, q9MassFloorForCorrection)
q9VelocityLimitedCells    : active kick clipped by q9CorrectionVelocityLimiter
```

## Recommended verification

From the repository root:

```bash
./scripts/build_src_mpcd_base.sh
./build/validate_elliptic_projection

git grep -n "q9LowMassTreatment\|q9MassFloorForCorrection\|q9LowMassRampStart\|q9LowMassRampEnd" -- src/q9_projection_adapter.cpp include/q9_projection_adapter.h include/runtime_summary.h src/runtime_summary.cpp
```

A short diagnostic run can reuse the existing 0069 runner, which already writes the ramp/floor parameters:

```bash
CASE_STEPS=1000 \
SUMMARY_EVERY=100 \
DUMP_STATE_EVERY=500 \
NUM_THREADS=8 \
AUTO_ANALYZE=1 \
./scripts/run_backward_step_mass_budget_viz_0069.sh
```

For the comparative run matching the previous diagnostic:

```bash
CASE_STEPS=8000 \
SUMMARY_EVERY=250 \
DUMP_STATE_EVERY=1000 \
NUM_THREADS=8 \
AUTO_ANALYZE=1 \
./scripts/run_backward_step_mass_budget_viz_0069.sh
```

Check the new columns in each case summary:

```bash
python3 - <<'PY'
import pandas as pd
from pathlib import Path
root = Path('runs/backward_step_mass_budget_viz_0069')
for path in sorted(root.glob('backstep_*/summary.csv')):
    df = pd.read_csv(path)
    last = df.iloc[-1]
    cols = [
        'q9Applied',
        'q9LowMassSuppressedCells',
        'q9LowMassRampedCells',
        'q9MassFloorAppliedCells',
        'q9VelocityLimitedCells',
        'q9CorrectionVelocityRawRms',
        'q9CorrectionVelocityRms',
        'q9MassFloorForCorrection',
        'q9LowMassRampStart',
        'q9LowMassRampEnd',
    ]
    print('\n', path.parent.name)
    print(last[[c for c in cols if c in df.columns]].to_string())
PY
```

MATLAB post-processing remains:

```matlab
cd matlab
R = analyze_backward_step_mass_budget_0069('root','..','runRoot','runs/backward_step_mass_budget_viz_0069');
V = make_backward_step_visual_report_0069('root','..','runRoot','runs/backward_step_mass_budget_viz_0069');
```
