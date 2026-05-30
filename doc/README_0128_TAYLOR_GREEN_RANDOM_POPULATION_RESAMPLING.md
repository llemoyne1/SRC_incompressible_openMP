# 0128 — Taylor–Green random-population resampling validation

This validation keeps the current OpenMP workflow:

- MATLAB prepares the `.smpcd` initial state in `../init/**` when launched from `matlab/`.
- Bash only writes `.kv` parameter files and launches the C++ executable.
- MATLAB post-processes and visualizes the output files in `../runs/**`.

The case is periodic in both directions and deliberately avoids walls, inlet/outlet and immersed solids.  Unlike the 0127 void/rich block case, the initial Fluid population is spatially random and bounded cell by cell.  The total Fluid particle count remains exactly `Nx*Ny*gamma`.

## 1. Prepare the initial state from MATLAB

From the repository root:

```bash
cd matlab
```

Then in MATLAB:

```matlab
prepare_taylor_green_random_population_resampling_0128( ...
    'output', '../init/taylor_green_random_population_resampling_0128/initial_state_tg_random_pop_0128.smpcd', ...
    'Nx', 32, ...
    'Ny', 32, ...
    'gamma', 20, ...
    'populationStd', 6.0, ...
    'populationMin', 4, ...
    'populationMax', 36, ...
    'flowAmplitude', 0.08, ...
    'kBT', 0.001, ...
    'seed', 1280128, ...
    'makePreview', true);
```

This writes:

```text
../init/taylor_green_random_population_resampling_0128/initial_state_tg_random_pop_0128.smpcd
../init/taylor_green_random_population_resampling_0128/initial_random_population_layout_0128.csv
```

## 2. Launch OpenMP from Bash

From the repository root:

```bash
./scripts/build_src_mpcd_base.sh

TG_STEPS=200 \
TG_DUMP_EVERY=50 \
TG_SUMMARY_EVERY=1 \
TG_THREADS=4 \
./scripts/run_taylor_green_random_population_resampling_validation_0128.sh
```

The launcher writes and runs three cases:

```text
runs/taylor_green_random_population_resampling_0128/classic
runs/taylor_green_random_population_resampling_0128/q6
runs/taylor_green_random_population_resampling_0128/q6_resampling
```

The resampling case uses tighter thresholds by default:

```text
resamplingPoorCellMassFraction = 0.90
resamplingRichCellMassFraction = 1.10
```

## 3. Analyze from MATLAB

From the repository root:

```bash
cd matlab
```

Then in MATLAB:

```matlab
analyze_taylor_green_random_population_resampling_0128('../runs/taylor_green_random_population_resampling_0128');
```

The additional 0128 trigger summary is:

```text
../runs/taylor_green_random_population_resampling_0128/analysis/tg_random_population_trigger_summary_0128.csv
```

Key quantities to inspect are:

- final and maximum `resampMRelRms`;
- total extraction and insertion operations;
- total remapped and thermal-renormalized cells;
- total mass-guard adjusted particles;
- final Taylor–Green amplitude/correlation from the 0126 analyzer.
