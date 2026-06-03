# 0131 — Poiseuille wallVP validation for OpenMP resampling

This validation is the first wall-bounded hydrodynamic case for the OpenMP
weighted-resampling branch after the periodic Taylor--Green checks.

The workflow follows the project convention:

1. MATLAB prepares the `.smpcd` input state in `../init/**`.
2. Bash writes `params_*.kv` and launches `build/src_mpcd_base`.
3. MATLAB post-processes `../runs/**`.

The C++ executable does not generate the initial state.

## Prepare the initial state

From the repository root:

```bash
cd matlab
```

Then in MATLAB:

```matlab
prepare_poiseuille_wallvp_resampling_0131( ...
    'output', '../init/poiseuille_wallvp_resampling_0131/initial_state_poiseuille_wallvp_0131.smpcd', ...
    'Lx', 2.0, 'Ly', 1.0, ...
    'Nx', 64, 'Ny', 32, 'gamma', 20, ...
    'kBT', 0.001, 'seed', 1310131);
```

## Run the OpenMP cases

From the repository root:

```bash
./scripts/build_src_mpcd_base.sh

POIS_STEPS=3000 \
POIS_DUMP_EVERY=100 \
POIS_SUMMARY_EVERY=10 \
POIS_THREADS=8 \
POIS_BODY_ACCEL=0.02 \
./scripts/run_poiseuille_wallvp_resampling_validation_0131.sh
```

The script launches:

- `classic`: compressible SRC/MPCD with periodic-x, solid-y walls and wallVP coupling;
- `q6`: Q6 projection without resampling;
- `q6_resampling`: Q6 plus weighted resampling, mass cadence and thermal renormalization.

The default wall model is `bcY=solid`, `wallAccommodation=1`, `wallVpGamma=gamma`.

## Post-process

From the repository root:

```bash
cd matlab
```

Then in MATLAB:

```matlab
analyze_poiseuille_wallvp_resampling_0131('../runs/poiseuille_wallvp_resampling_0131');
```

The analysis writes:

- `analysis/poiseuille_summary_0131.csv`;
- `analysis/poiseuille_profile_<case>.csv`;
- visible figures for profiles, time series and final fields.

The Poiseuille fit uses

```text
Ux(y) = Uslip + C y (Ly-y),       nu_eff = bodyAccelerationX/(2C).
```

Use `excludeWallCells` in the MATLAB analyzer to control the fit window near the walls.
