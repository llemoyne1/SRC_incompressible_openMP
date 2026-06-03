# 0139 — Injection/fill validation from an initially inactive domain

This validation reproduces the MATLAB weighted-resampling `run_resamp_injection_fill_demo` idea in the OpenMP workflow:

```text
MATLAB prepares init/**/.smpcd
bash writes params.kv and launches src_mpcd_base
MATLAB analyzes runs/**
```

The initial state contains a full preallocated pool of particles with
`role=Inactive`.  No real fluid mass is present at `t=0`.  A one-cell hard inlet
aperture injects active `Fluid` particles into an otherwise empty channel.  The
front then propagates downstream and progressively wets the domain.

This is a stress test for:

- inlet/outlet hard-cell-density injection;
- initially empty/inactive domains;
- wet/dry semantics (`resamplingWetMaskMode=occupied`);
- exclusion of `Inactive` particles from deposits, collisions, Q6 and diagnostics;
- Q6 + resampling during a strongly transient fill;
- mass control only on already wet cells.

Dry cells must not be forced to `Mtarget`; the fill should occur through injected
and transported active particles.

## 1. Prepare initial state with MATLAB

From the repository root:

```bash
cd matlab
```

Then in MATLAB:

```matlab
prepare_injection_fill_resampling_0139( ...
    'output', '../init/injection_fill_resampling_0139/initial_state_injection_fill_0139.smpcd', ...
    'Lx', 4.0, 'Ly', 1.0, ...
    'Nx', 192, 'Ny', 48, 'gamma', 20, ...
    'capacityMultiplier', 1.0, ...
    'kBT', 0.001, ...
    'seed', 1390139, ...
    'inletYCenter', 0.5, ...
    'inletHeightCells', 1.0, ...
    'makePreview', true);
```

The generated state is written in OpenMP `.smpcd` V2 format with:

```text
role = 0  for all particles initially
mass = 1
type = 0
```

## 2. Run OpenMP

From the repository root:

```bash
./scripts/build_src_mpcd_base.sh

FILL_STEPS=3000 \
FILL_DUMP_EVERY=100 \
FILL_SUMMARY_EVERY=25 \
FILL_THREADS=8 \
./scripts/run_injection_fill_resampling_validation_0139.sh
```

For a shorter smoke:

```bash
FILL_STEPS=1000 \
FILL_DUMP_EVERY=100 \
FILL_SUMMARY_EVERY=10 \
FILL_THREADS=8 \
./scripts/run_injection_fill_resampling_validation_0139.sh
```

Important parameters exposed by the script:

```bash
FILL_INLET_UX=0.10
FILL_INLET_CENTER_Y=0.5
FILL_INLET_HEIGHT_CELLS=1.0
FILL_INLET_RESERVOIR_CELLS=1
FILL_MASS_RENORM_PERIOD=10
```

The script launches:

```text
classic
q6
q6_resampling
```

## 3. MATLAB analysis

From the repository root:

```bash
cd matlab
```

Then:

```matlab
analyze_injection_fill_resampling_0139('../runs/injection_fill_resampling_0139');
```

The analysis writes:

```text
runs/injection_fill_resampling_0139/analysis/injection_fill_summary_0139.csv
runs/injection_fill_resampling_0139/analysis/injection_fill_frame_metrics_0139_*.csv
runs/injection_fill_resampling_0139/analysis/injection_fill_0139_progress.png
runs/injection_fill_resampling_0139/analysis/injection_fill_0139_final_fields_*.png
```

## Diagnostics to inspect

Primary indicators:

```text
wetCellFraction
frontX
nFluid
nInactive
resampMRelRms
totalInletInserted
totalOutletDeleted
totalExtracted / totalInserted
```

Expected behavior:

- at `t=0`, the domain contains no `Fluid` particles;
- the hard inlet aperture progressively creates a wet region;
- cells ahead of the front remain dry and are not forced to `Mtarget`;
- `q6_resampling` controls mass in wet cells better than `q6` alone;
- the run should not turn empty cells into artificial obstacles or pressure sinks.

