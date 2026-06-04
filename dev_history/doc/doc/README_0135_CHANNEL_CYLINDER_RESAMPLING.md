# 0135 — Channel-cylinder validation for Q6 + weighted resampling

This validation case is the next step after:

- 0131: Poiseuille wallVP, no immersed solid;
- 0134: periodic immersed cylinder, no solid channel walls.

The 0135 case combines:

- periodic streamwise direction `x`;
- solid top/bottom channel walls with wallVP coupling;
- a fixed immersed circular cylinder;
- classic / Q6 / Q6 + weighted resampling comparison.

It deliberately avoids inlet/outlet at this stage.  The current Q6 open-boundary path has stricter immersed-solid restrictions; this case first validates the combined wall + cylinder + resampling physics in a closed periodic channel.

## Generate the initial state with MATLAB

From the repository root:

```bash
cd matlab
```

Then in MATLAB:

```matlab
prepare_channel_cylinder_resampling_0135( ...
    'output', '../init/channel_cylinder_resampling_0135/initial_state_channel_cylinder_0135.smpcd', ...
    'Lx', 2.0, 'Ly', 1.0, ...
    'Nx', 96, 'Ny', 48, 'gamma', 20, ...
    'cylinderCx', 0.65, 'cylinderCy', 0.5, 'cylinderR', 0.12, ...
    'populationMode', 'random', ...
    'populationStd', 6.0, 'populationMin', 4, 'populationMax', 36, ...
    'initialProfile', 'poiseuille', 'initialMeanUx', 0.02, ...
    'kBT', 0.001, ...
    'seed', 1350135, ...
    'makePreview', true);
```

This writes:

```text
../init/channel_cylinder_resampling_0135/initial_state_channel_cylinder_0135.smpcd
../init/channel_cylinder_resampling_0135/initial_channel_cylinder_layout_0135.csv
```

## Run OpenMP

From the repository root:

```bash
./scripts/build_src_mpcd_base.sh

CCYL_STEPS=3000 \
CCYL_DUMP_EVERY=100 \
CCYL_SUMMARY_EVERY=25 \
CCYL_THREADS=8 \
./scripts/run_channel_cylinder_resampling_validation_0135.sh
```

For a quick smoke:

```bash
CCYL_STEPS=1000 \
CCYL_DUMP_EVERY=250 \
CCYL_SUMMARY_EVERY=10 \
CCYL_THREADS=8 \
./scripts/run_channel_cylinder_resampling_validation_0135.sh
```

The script launches:

```text
classic
q6
q6_resampling
```

The default run uses:

```text
bcLeft  = periodic
bcRight = periodic
bcBottom = solid
bcTop    = solid
projectionOperator = channel_fv_cg
immersedSolidShape = circle
wallAccommodation = 1
wallVpGamma = gamma
bodyAccelerationX = 0.01
```

## Analyze with MATLAB

From the repository root:

```bash
cd matlab
```

Then:

```matlab
analyze_channel_cylinder_resampling_0135('../runs/channel_cylinder_resampling_0135');
```

The analyzer writes:

```text
../runs/channel_cylinder_resampling_0135/analysis/channel_cylinder_summary_0135.csv
../runs/channel_cylinder_resampling_0135/analysis/channel_cylinder_metrics_classic.csv
../runs/channel_cylinder_resampling_0135/analysis/channel_cylinder_metrics_q6.csv
../runs/channel_cylinder_resampling_0135/analysis/channel_cylinder_metrics_q6_resampling.csv
../runs/channel_cylinder_resampling_0135/analysis/channel_cylinder_0135_timeseries.png
../runs/channel_cylinder_resampling_0135/analysis/channel_cylinder_0135_final_fields_*.png
../runs/channel_cylinder_resampling_0135/analysis/channel_cylinder_0135_profiles.png
```

## Main diagnostics

Inspect:

- `finalSolidLeakMass`, `maxSolidLeakMass`: mass found in cylinder-masked cells;
- `finalQ6Div`: projected divergence diagnostic;
- `finalResampMRelRms`: real-fluid mass control;
- `finalWakeOmegaRms`: wake activity behind the cylinder;
- `finalWakeBackflowFraction`: simple recirculation proxy;
- `finalWallBandUxMean`, `finalWallBandMassStd`: wall-band behavior;
- `totalExtracted`, `totalInserted`, `totalRemapCells`, `totalMassGuardAdjusted`: activity of the weighted resampling pipeline.

Expected qualitative behavior:

- `q6` should reduce divergence relative to `classic`;
- `q6_resampling` should keep a Q6-like velocity/wake field;
- `q6_resampling` should drive `finalResampMRelRms` close to roundoff in active fluid cells;
- cylinder leakage should remain comparable to or better than Q6.
