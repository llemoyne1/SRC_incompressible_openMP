# 0493n — Reduced resampled-fluid go/no-go sweep

## Purpose

This additive qualification does **not** attempt to prove that active resampling is identical to pure SRC. The project history already establishes a credible nominal mono-species fluid at `64x64`, `gamma=20`, with the historical population band `14/20/26`, and a Poiseuille effective-viscosity difference of roughly four percent. It also records that the CUDA 0300 Taylor--Green threshold sweep was short and essentially passive.

0493n targets the remaining question on the current resident-CUDA implementation:

> Does active resampling define a stable, calibratable effective fluid when population resolution, actual split/merge cadence, and one spatial-scale confirmation are varied?

The analysis therefore compares every resampled run with a pure-SRC run at the **same** grid and gamma. It does not require raw viscosity to be invariant when gamma or the MPCD cell scale changes.

## No solver modification

The patch adds only:

- `scripts/run_0493n_resampled_fluid_reduced_sweep.sh`
- `scripts/analyze_0493n_resampled_fluid_reduced_sweep.py`
- this README.

No source file, CUDA kernel, collision operator, resampling operation, Q6 path, thermostat, or boundary condition is modified. No rebuild is required.

## Matrix

### Core stage — eight simulations

| Case | Grid | gamma | actual CUDA 0297 guard cadence | Modes |
|---|---:|---:|---:|---|
| `g64_g10_e1` | 64x64 | 10 | every step | SRC + resampling |
| `g64_g20_e1` | 64x64 | 20 | every step | SRC + resampling |
| `g64_g40_e1` | 64x64 | 40 | every step | SRC + resampling |
| `g64_g20_e5` | 64x64 | 20 | every 5 steps | resampling |
| `g64_g20_e20` | 64x64 | 20 | every 20 steps | resampling |

The population band is the historical relative band:

```text
Nmin/Ntarget/Nmax = 0.70 gamma / gamma / 1.30 gamma
```

Thus the default bands are `7/10/13`, `14/20/26`, and `28/40/52`.

### Grid stage — two additional simulations

| Case | Grid | gamma | cadence | Modes |
|---|---:|---:|---:|---|
| `g128_g20_e1` | 128x128 | 20 | every step | SRC + resampling |

The grid check compares the **paired resampling perturbation**

```text
abs(nu_resampling - nu_SRC) / nu_SRC
```

between 64x64 and 128x128. Raw MPCD viscosities are not treated as grid-invariant because changing the collision-cell scale changes the kinetic fluid unless the full nondimensional parameter set is rescaled.

## Default physical case

- mono-species resident CUDA path (`mono_species`)
- periodic, unforced Taylor--Green decay
- TG mode 2
- `U0=0.08`
- thermal amplitude `0.04`
- particle mass exactly 1 initially
- Q6 off
- thermostat off
- empty-refill configured by the common runner but required to remain inactive by the inherited 0493k audit
- 600 steps
- dump every 20 steps
- one seed for the initial go/no-go screen

## Staged execution

Preflight core:

```bash
STAGE=core PREFLIGHT_ONLY=1 LIVE_PROGRESS=1 \
  bash scripts/run_0493n_resampled_fluid_reduced_sweep.sh
```

Run core:

```bash
STAGE=core CLEAN_RUN_ROOT=1 LIVE_PROGRESS=1 \
  bash scripts/run_0493n_resampled_fluid_reduced_sweep.sh
```

If the core stage is acceptable, append the 128x128 stage to the same root:

```bash
STAGE=grid LIVE_PROGRESS=1 \
  bash scripts/run_0493n_resampled_fluid_reduced_sweep.sh
```

For `STAGE=grid`, `CLEAN_RUN_ROOT` defaults to zero so that the core results and manifest are preserved. `STAGE=all` runs all ten simulations from a clean root.

A single case can be selected with, for example:

```bash
STAGE=core CASE_FILTER=g64_g20_e1 LIVE_PROGRESS=1 \
  bash scripts/run_0493n_resampled_fluid_reduced_sweep.sh
```

## Outputs

At sweep root:

```text
case_manifest_0493n.csv
status_0493n.csv
resampled_fluid_0493n_per_run.csv
resampled_fluid_0493n_pairwise.csv
resampled_fluid_0493n_checks.csv
resampled_fluid_0493n.json
resampled_fluid_0493n.md
```

Each case also retains the inherited 0493k and 0493l outputs.

## Interpretation

The main observables are:

- positive, well-fitted effective viscosity;
- TG curve error relative to the matching SRC case;
- resampling-induced viscosity shift relative to matching SRC;
- sensitivity to actual split/merge cadence;
- support maintenance and empty cells;
- thermal and kinetic drift;
- active split/merge count;
- particle-weight CV2 and ESS/N as diagnostics, not automatic physical failures.

The core stage can return `GO_PROVISIONAL_CORE`, `WATCH`, `INCONCLUSIVE`, or `NO_GO`. A complete core+grid campaign can return `GO`, `WATCH`, `INCONCLUSIVE`, or `NO_GO`.
