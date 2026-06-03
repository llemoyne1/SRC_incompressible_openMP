# 0126 — Periodic Taylor--Green validation for OpenMP resampling

Patch 0126 introduces the first physical validation case for the OpenMP
weighted-resampling branch.  The case is deliberately fully periodic in `x`
and `y` so failures cannot be attributed to inlet/outlet, wall or immersed-solid
boundary conditions.

## Scope

The patch adds:

- a MATLAB generator for a V2 `.smpcd` Taylor--Green initial state with all
  particles marked `role=Fluid`;
- V1/V2 MATLAB `.smpcd` readers/writers compatible with the OpenMP resampling
  branch;
- a `bin_smpcd_state(...,'fluidOnly',true)` path so latent/inactive slots are
  excluded from post-processing fields;
- a bash runner for three periodic cases:
  - `classic`: compressible SRC/MPCD baseline;
  - `q6`: Q6 velocity projection without resampling;
  - `q6_resampling`: Q6 plus extraction/insertion/remap/thermal renormalization
    and mass guard;
- a MATLAB analyzer that computes Taylor--Green modal amplitude, pattern
  correlation, grid divergence, vorticity RMS, runtime Q6 diagnostics and
  resampling diagnostics, then writes CSV tables and visible figures.

No new boundary condition or immersed-solid path is exercised by this patch.

## Main command

```bash
./scripts/run_taylor_green_resampling_validation_0126.sh
```

Useful overrides:

```bash
TG_NX=64 TG_NY=64 TG_GAMMA=20 TG_STEPS=3000 TG_DUMP_EVERY=100 TG_THREADS=8 \
./scripts/run_taylor_green_resampling_validation_0126.sh
```

By default the script uses:

```text
Nx=Ny=32
gamma=20
U0=0.08
kBT=0.001
nSteps=1000
dumpStateEvery=100
summaryEvery=10
```

The default run root is:

```text
runs/taylor_green_resampling_0126
```

## Generated outputs

The runner creates:

```text
runs/taylor_green_resampling_0126/initial_state_tg_0126.smpcd
runs/taylor_green_resampling_0126/classic/
runs/taylor_green_resampling_0126/q6/
runs/taylor_green_resampling_0126/q6_resampling/
runs/taylor_green_resampling_0126/analysis/
```

The analysis directory contains:

```text
tg_metrics_classic.csv
tg_metrics_q6.csv
tg_metrics_q6_resampling.csv
tg_summary.csv
tg_0126_amplitude_correlation.png
tg_0126_div_mass_population.png
tg_0126_resampling_operations.png
tg_0126_final_fields_*.png
```

## Expected checks

The validation is not intended to certify transport coefficients yet.  It checks
that, in a clean periodic setting:

1. the Taylor--Green modal amplitude remains coherent;
2. the Q6 residual/divergence diagnostics remain controlled;
3. `q6_resampling` keeps `resampMRelRms` near roundoff after remap;
4. inactive slots created by extraction are ignored by MATLAB field binning;
5. cell mass and population fields remain interpretable in the final figures.

The first quantity to inspect is:

```text
analysis/tg_summary.csv
```

Then compare:

```text
finalAmplitude, amplitudeRatio, finalCorrelation,
finalDivRms, finalResampMRelRms, totalExtracted, totalInserted
```

between `q6` and `q6_resampling`.

## MATLAB entry points

Manual state generation:

```matlab
addpath('matlab');
generate_taylor_green_resampling_state_0126( ...
    'output','runs/taylor_green_resampling_0126/initial_state_tg_0126.smpcd', ...
    'Nx',64,'Ny',64,'gamma',20,'flowAmplitude',0.08,'kBT',0.001);
```

Manual post-processing:

```matlab
addpath('matlab');
analyze_taylor_green_resampling_0126('runs/taylor_green_resampling_0126');
```

## Notes on `.smpcd` V2 and roles

Patch 0126 updates the MATLAB reader/writer to understand the V2 payload used by
OpenMP resampling:

```text
x, y, vx, vy, type, mass, role
```

with:

```text
0 = Inactive
1 = Fluid
2 = Latent
```

`bin_smpcd_state` now defaults to `fluidOnly=true`, so dormant slots do not
pollute density, velocity, vorticity or Taylor--Green modal diagnostics.
