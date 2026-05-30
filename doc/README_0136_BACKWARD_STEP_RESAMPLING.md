# 0136 — Backward-facing step with Q6 + weighted resampling

This validation case is intended to produce richer separated-flow structures than the periodic/channel cylinder tests while preserving the established workflow:

- MATLAB prepares the `.smpcd` initial state in `../init/**`.
- Bash writes `params*.kv` and launches the C++ executable.
- MATLAB post-processes `../runs/**`.

The C++ code is not modified by this patch.

## Why a backward-facing step instead of open-boundary cylinder?

The current C++ open-boundary validation path accepts Q6/Q9 inlet/outlet with immersed solids only for a fixed rectangular/step solid with a hard-cell-density inlet reservoir. A circular open-boundary cylinder would require additional C++ support. The backward-facing step is therefore the most relevant next case for testing:

- inlet/outlet;
- top/bottom solid walls and wallVP;
- fixed immersed rectangle;
- separated recirculating flow;
- Q6 + resampling in a non-periodic geometry.

## Generate the initial state

From the repository root:

```bash
cd matlab
```

Then in MATLAB:

```matlab
prepare_backward_step_resampling_0136( ...
    'output', '../init/backward_step_resampling_0136/initial_state_backward_step_0136.smpcd', ...
    'Lx', 4.0, 'Ly', 1.0, ...
    'Nx', 192, 'Ny', 48, 'gamma', 20, ...
    'stepXMax', 0.8, 'stepHeight', 0.5, ...
    'populationMode', 'random', ...
    'populationStd', 6.0, 'populationMin', 4, 'populationMax', 36, ...
    'initialProfile', 'inlet_plug', 'initialMeanUx', 0.04, ...
    'kBT', 0.001, ...
    'seed', 1360136, ...
    'makePreview', true);
```

## Run OpenMP

From the repository root:

```bash
./scripts/build_src_mpcd_base.sh

BSTEP_STEPS=3000 \
BSTEP_DUMP_EVERY=100 \
BSTEP_SUMMARY_EVERY=25 \
BSTEP_THREADS=8 \
./scripts/run_backward_step_resampling_validation_0136.sh
```

A short smoke run:

```bash
BSTEP_STEPS=1000 \
BSTEP_DUMP_EVERY=250 \
BSTEP_SUMMARY_EVERY=10 \
BSTEP_THREADS=8 \
./scripts/run_backward_step_resampling_validation_0136.sh
```

More aggressive separated flow:

```bash
BSTEP_INLET_UX=0.12 \
BSTEP_STEPS=3000 \
BSTEP_DUMP_EVERY=100 \
BSTEP_SUMMARY_EVERY=25 \
BSTEP_THREADS=8 \
./scripts/run_backward_step_resampling_validation_0136.sh
```

## Post-process

From the repository root:

```bash
cd matlab
```

Then:

```matlab
analyze_backward_step_resampling_0136('../runs/backward_step_resampling_0136');
```

The analysis writes:

- `../runs/backward_step_resampling_0136/analysis/backward_step_summary_0136.csv`
- `backstep_profile_*.csv`
- `backstep_0136_final_fields_*.png`
- `backstep_0136_profiles.png`
- `backstep_0136_timeseries.png`

## Key diagnostics

The most important diagnostics are:

- `finalRecircBackflowFraction`;
- `finalRecircMinUx`;
- `finalShearOmegaRms`;
- `finalWakeOmegaRms`;
- `finalSolidLeakMass`;
- `finalResampMRelRms`;
- `finalQ6Div`;
- `totalExtracted`, `totalInserted`, `totalRemapCells`, `totalMassGuardAdjusted`.
