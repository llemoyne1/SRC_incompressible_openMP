# 0138 — Open-channel cylinder resampling validation

This validator is the first inlet/outlet cylinder wake case for the OpenMP weighted-resampling branch.
It is intended to test, in one controlled case:

- inlet/outlet boundary conditions;
- top/bottom solid walls with wallVP;
- immersed circular solid reflection/coupling;
- Q6 elliptic projection with immersed-solid masking;
- weighted resampling in an open, non-periodic streamwise geometry.

It does not modify the C++ kernel. MATLAB prepares the initial `.smpcd` file and post-processes the dumps; bash only writes `.kv` files and launches `src_mpcd_base`.

## MATLAB preparation

From the repository root:

```bash
cd matlab
```

Then in MATLAB:

```matlab
prepare_open_channel_cylinder_resampling_0138( ...
    'output', '../init/open_channel_cylinder_resampling_0138/initial_state_open_channel_cylinder_0138.smpcd', ...
    'Lx', 4.0, 'Ly', 1.0, ...
    'Nx', 192, 'Ny', 48, 'gamma', 20, ...
    'cylinderCx', 1.0, 'cylinderCy', 0.5, 'cylinderR', 0.10, ...
    'populationMode', 'random', ...
    'populationStd', 6.0, 'populationMin', 4, 'populationMax', 36, ...
    'initialProfile', 'poiseuille', 'initialMeanUx', 0.05, ...
    'kBT', 0.001, ...
    'seed', 1380138, ...
    'makePreview', true);
```

## OpenMP run

From the repository root:

```bash
./scripts/build_src_mpcd_base.sh

OCYL_STEPS=3000 \
OCYL_DUMP_EVERY=100 \
OCYL_SUMMARY_EVERY=25 \
OCYL_THREADS=8 \
./scripts/run_open_channel_cylinder_resampling_validation_0138.sh
```

A shorter smoke run is:

```bash
OCYL_STEPS=1000 \
OCYL_DUMP_EVERY=250 \
OCYL_SUMMARY_EVERY=10 \
OCYL_THREADS=8 \
./scripts/run_open_channel_cylinder_resampling_validation_0138.sh
```

More aggressive wake runs can be attempted by raising the inlet velocity:

```bash
OCYL_INLET_UX=0.10 \
OCYL_STEPS=5000 \
OCYL_DUMP_EVERY=250 \
OCYL_SUMMARY_EVERY=25 \
OCYL_THREADS=8 \
./scripts/run_open_channel_cylinder_resampling_validation_0138.sh
```

## MATLAB analysis

From the repository root:

```bash
cd matlab
```

Then in MATLAB:

```matlab
analyze_open_channel_cylinder_resampling_0138('../runs/open_channel_cylinder_resampling_0138');
```

The analyzer writes:

- `open_channel_cylinder_summary_0138.csv`;
- one metrics CSV per case;
- one final profile CSV per case;
- final field figures with the cylinder overlay;
- time-series figures for mean velocity, wake vorticity, backflow fraction, mass residual, and solid leakage.

## Key diagnostics

Primary success criteria:

- no major increase of `solidLeakMass` in `q6_resampling` relative to `q6`;
- `q6DivAfterProjectedFluxRms` remains controlled;
- `resampMRelRms` is strongly reduced in `q6_resampling`;
- wake diagnostics (`wakeUyRms`, `wakeOmegaRms`, `wakeBackflowFraction`) remain physically credible and not artificially suppressed;
- cost remains comparable to the optimized resampling branch after patches 0132/0133.

This case is a preliminary von-Karman-like test. If it stays stable and produces coherent wake fluctuations, the next stage can add longer-domain runs and probe-based spectral diagnostics.
