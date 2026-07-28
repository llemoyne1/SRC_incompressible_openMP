# 0493w0 — Darcy kinetic-regime sweep before wall support repair

## Purpose

This runner tests whether the depleted wake and inlet-lip accumulation of the
segmented Darcy-cylinder case are primarily caused by an extreme SRC/MPCD
regime rather than by a missing wall-specific resampling mechanism.

The sweep changes:

- initial and thermostat target `kBT`;
- grid resolution;
- physical time step `dt`;
- two optional `alpha*dt` controls for the Brinkman/Darcy forcing.

The support repair and every other mutating resampling mechanism are disabled.
Each case writes one final fluid-only `.smpcd` dump, and the analyzer deposits
that state directly on the physical grid.

## Default screen

The default profile contains 15 cases and observes each case until `t=0.8`:

- `dt=0.0005`: 1600 steps;
- `dt=0.001`: 800 steps;
- `dt=0.002`: 400 steps.

The baseline no-repair timing measured previously on the target GPU gives an
estimated wall time of about 13–15 minutes. The runner stops launching new
cases close to the default 1200 s budget rather than killing a case in progress.

A shorter profile is available with:

```bash
SWEEP_PROFILE=quick LIVE_PROGRESS=1 \
  bash scripts/run_0493w0_darcy_kinetic_regime_sweep.sh
```

## Dimensionless quantities

The preflight and final analysis report:

- cylinder resolution `D/a`;
- 2-D SRD/MPCD viscosity estimate split into kinetic and collisional parts;
- cylinder Reynolds estimate `Re_D = U D / nu`;
- ideal-gas 2-D sound-speed proxy `c_s = sqrt(2 kBT/m)`;
- corresponding Mach proxy;
- one-component and 2-D rms thermal displacement per cell;
- advective cell CFL;
- thermal Knudsen proxy based on cylinder diameter;
- `alpha*dt` and an effective Darcy-number estimate;
- number of cylinder transit times covered by the run.

The viscosity formula is a regime-positioning estimate for standard 2-D SRD
with random grid shift and Poisson cell occupancy. It is not a replacement for
a measured Poiseuille viscosity. Quantitative physical comparison should use a
Poiseuille calibration at the same `Nx`, `Ny`, `dt`, `kBT`, `gamma`, rotation
angle, thermostat and wall treatment.

The Mach number is also labelled a proxy. The current executable does not
measure the acoustic speed, and wall virtual particles plus Darcy penalization
can change the effective acoustic response.

## Spatial diagnostics

The analyzer reads the final `.smpcd` dump and reports metrics in:

- all fluid cells;
- a two-cell cylinder interface band;
- a four-cell cylinder halo;
- the near wake over one cylinder diameter;
- the wake over two cylinder diameters;
- side-control bands above and below the wake;
- a cylinder-shoulder control region;
- an upstream center control region;
- the lower inlet lip;
- the external-wall halo;
- the far bulk.

Important outputs include:

- empty and poor-cell fractions;
- mean count and mass per cell;
- wake-to-side support and mass ratios;
- mass-weighted mean velocity;
- cross-stream to streamwise cell-velocity ratio;
- thermal anisotropy;
- inward/outward cross-stream flux proxies into the wake.

## Outputs

Under `runs/0493w0_darcy_kinetic_regime_sweep/`:

- `sweep_manifest.csv` — exact case matrix;
- `run_status.csv` — completion and wall time per case;
- `analysis/dimensionless_preflight.csv` — input regime before runs;
- `analysis/dimensionless_groups.csv` — input and final-state regime estimates;
- `analysis/final_global_metrics.csv` — final runtime diagnostics;
- `analysis/zone_metrics.csv` — long-format spatial metrics;
- `analysis/sweep_summary.csv` — one compact row per case.

## Run

```bash
LIVE_PROGRESS=1 \
  bash scripts/run_0493w0_darcy_kinetic_regime_sweep.sh
```

Preflight only:

```bash
PREFLIGHT_ONLY=1 \
  bash scripts/run_0493w0_darcy_kinetic_regime_sweep.sh
```

## Interpretation

The default matrix is designed to separate three effects:

1. **Compressibility / thermal isotropization**: the `kBT` axis lowers the
   ideal-gas Mach proxy from about 3.35 to 0.34 while changing the collisional
   viscosity only weakly in the current short-mean-free-path regime.
2. **Hydrodynamic Reynolds scale**: finer grids and larger `dt` lower the
   collisional viscosity estimate, moving `Re_D` from about 4 to about 56.
3. **Inter-cell communication**: the combined hot, fine-grid, larger-`dt` case
   increases the 2-D rms thermal displacement from roughly 0.006 cell to more
   than 0.2 cell per step.

A wall-support mechanism becomes justified only if the interface/wake deficit
persists in cases that simultaneously have a moderate Mach proxy, adequate
cylinder resolution and non-negligible inter-cell thermal displacement.
