# 0078 — Gamma-relative Q9 low-mass thresholds

## Purpose

This patch makes the Q9 low-mass safety parameters scale with the reference cell occupancy `gamma`.  The goal is to keep the same dimensionless method policy when changing the particle population per cell, instead of retuning absolute thresholds case by case.

The previous hard-inlet runs at `gamma=20` used the absolute values:

```text
q9LowMassRampStart        = 1
q9LowMassRampEnd          = 8
q9MassFloorForCorrection  = 8
q9MinCellMassForCorrection = 8
```

These correspond to:

```text
rampStart/gamma = 0.05
rampEnd/gamma   = 0.40
floor/gamma     = 0.40
min/gamma       = 0.40
```

The new defaults used by the Poiseuille hard-inlet/free-outlet validation script are therefore:

```text
q9LowMassRampStartOverGamma        = 0.05
q9LowMassRampEndOverGamma          = 0.40
q9MassFloorForCorrectionOverGamma  = 0.40
q9MinCellMassForCorrectionOverGamma = 0.40
```

For `gamma=20`, the effective values remain `1/8/8/8`.  For `gamma=30`, they become `1.5/12/12/12`.  For `gamma=40`, they become `2/16/16/16`.

## New parameters

```text
q9ReferenceGamma
q9MinCellMassForCorrectionOverGamma
q9MassFloorForCorrectionOverGamma
q9LowMassRampStartOverGamma
q9LowMassRampEndOverGamma
```

A negative `*OverGamma` value disables the relative form and keeps the corresponding absolute legacy parameter.  If `q9ReferenceGamma` is left at zero, the code uses `inletTargetOccupancy` as the reference gamma, which is the intended path for hard-inlet tests.

The runtime CSV columns keep their existing names:

```text
q9MinCellMassForCorrection
q9MassFloorForCorrection
q9LowMassRampStart
q9LowMassRampEnd
```

They now report the **effective absolute values** used by Q9 after gamma scaling.

## Updated Poiseuille hard-inlet/free-outlet script

The script:

```text
scripts/run_poiseuille_hard_inlet_free_outlet_validated_q9_0077.sh
```

now writes gamma-relative Q9 low-mass thresholds by default.  It also builds the default initial-state filename from `Nx`, `Ny`, `GAMMA`, `KBT`, and `INIT_UX`, so a `GAMMA=30` run no longer accidentally reuses the `g20` state filename.

## Gamma=30 conformity test

Generate the initial state from MATLAB:

```matlab
cd('/home/llemoyne/GitHub/SRC_incompressible_openMP-elliptic-q6/matlab')

generate_open_channel_classic_state( ...
    'output','../initial_state_poiseuille_hard_inlet_48x24_g30_kbt0p0025_ux0p05.smpcd', ...
    'Lx',2.0, ...
    'Ly',1.0, ...
    'Nx',48, ...
    'Ny',24, ...
    'gamma',30, ...
    'kBT',0.0025, ...
    'inletUx',0.05);

cd('..')
```

Smoke run:

```bash
RUN_ROOT=runs/poiseuille_hard_inlet_free_outlet_validated_q9_0078_g30_smoke \
GAMMA=30 \
CASE_STEPS=1000 \
SUMMARY_EVERY=25 \
DUMP_STATE_EVERY=500 \
NUM_THREADS=8 \
AUTO_ANALYZE=0 \
./scripts/run_poiseuille_hard_inlet_free_outlet_validated_q9_0077.sh
```

Main comparison run:

```bash
RUN_ROOT=runs/poiseuille_hard_inlet_free_outlet_validated_q9_0078_g30 \
GAMMA=30 \
CASE_STEPS=60000 \
SUMMARY_EVERY=100 \
DUMP_STATE_EVERY=5000 \
NUM_THREADS=8 \
AUTO_ANALYZE=0 \
./scripts/run_poiseuille_hard_inlet_free_outlet_validated_q9_0077.sh
```

Check the effective thresholds in the runtime summary:

```bash
python3 - <<'PY'
import pandas as pd
from pathlib import Path

root = Path('runs/poiseuille_hard_inlet_free_outlet_validated_q9_0078_g30')
for f in sorted(root.glob('*/summary_runtime.csv')):
    df = pd.read_csv(f)
    last = df.iloc[-1]
    cols = [
        'q9MinCellMassForCorrection',
        'q9MassFloorForCorrection',
        'q9LowMassRampStart',
        'q9LowMassRampEnd',
        'q9LowMassSuppressedCells',
        'q9LowMassRampedCells',
        'q9MassFloorAppliedCells',
    ]
    print('\n' + str(f))
    print(last[[c for c in cols if c in df.columns]].to_string())
PY
```

Expected effective thresholds for `gamma=30`:

```text
q9MinCellMassForCorrection = 12
q9MassFloorForCorrection   = 12
q9LowMassRampStart         = 1.5
q9LowMassRampEnd           = 12
```

## Commit suggestion

```bash
git add include/simulation_params.h \
        src/params_io_base.cpp \
        src/q9_projection_adapter.cpp \
        scripts/run_poiseuille_hard_inlet_free_outlet_validated_q9_0077.sh \
        doc/README_0078_GAMMA_RELATIVE_Q9_LOW_MASS.md

git commit -m "0078 scale Q9 low-mass thresholds with gamma"
```
