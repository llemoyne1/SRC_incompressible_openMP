# 0493x13c — SRC transport qualification

Campaign-only tooling. No files in `src/` or `include/` are changed.

## Hγ: multi-seed transverse viscosity versus gamma

Fixed microscopic point:
- rotation angle = 120 deg
- mean free path / cell = 0.48
- kBT = 0.125, particle mass = 1
- cell size h = 1/256
- transverse mode amplitude U0 = 0.05

Default axes:
- gamma = 6, 8, 10, 14, 20
- wavelength = 64 and 128 cells
- four paired seeds = 4931411..4931414

The runner is restartable (`CLEAN_ROOT=0`, `SKIP_EXISTING=1` by default) and creates a completion marker per sub-run.
The analyzer reuses the validated x13b shear fit, then reports mean/std/CV/95%-CI across seeds, Ny64-vs-Ny128 locality, and two cost proxies.

Outputs:
- `analysis/H_gamma_runs_0493x13c.csv`
- `analysis/H_gamma_wavelength_summary_0493x13c.csv`
- `analysis/H_gamma_qualification_0493x13c.csv`

`LOCAL_PASS` is a screening label, not a mathematical proof of the continuum limit. Default thresholds require both wavelength groups PASS and <=15% change in mean nuT.

## Cstat: statistically enriched longitudinal response

Fixed microscopic point is again angle=120 deg, lambda/h=0.48. Default fluids:
- A1 = gamma 20 reference
- G08 = gamma 8
- G10 = gamma 10

Default amplitudes are epsilon_rho = 0.04 and 0.08. The fractional/conservative x13b fix1 generator is mandatory.
Replicate counts target `gamma * Nrep ~= 240`:
- A1: 12 reps
- G08: 30 reps
- G10: 24 reps

The same replicate seed is reused between epsilon=.04 and .08 for a paired design.
The analysis keeps the existing 0493w1 longitudinal regression and adds 300 bootstrap resamples of the replicate ensemble.

Outputs:
- `analysis/Cstat_individual_replicates_0493x13c.csv`
- `analysis/Cstat_group_statistics_0493x13c.csv`
- `analysis/Cstat_fluid_qualification_0493x13c.csv`

Important fields include bootstrap CV and 95% percentile interval for cs and nuL, plus `nuLBoundaryFraction`, the fraction of bootstrap fits that hit the constrained `nuL=0` boundary.

The `nuLQualification` screening rules are intentionally conservative. A PASS requires both amplitudes to be pooled PASS, <=35% amplitude disagreement, <=35% bootstrap CV, <=10% `nuL=0` boundary hits and >=90% usable bootstrap fits. REVIEW relaxes those limits. `UNRESOLVED` means only that this protocol has not statistically resolved nuL; it does not invalidate the fluid.

## Typical workflow

```bash
bash scripts/check_0493x13c_transport_qualification.sh

PREFLIGHT_ONLY=1 bash scripts/run_0493x13c_H_gamma_multiseed.sh
LIVE_PROGRESS=1 bash scripts/run_0493x13c_H_gamma_multiseed.sh

PREFLIGHT_ONLY=1 bash scripts/run_0493x13c_C_longitudinal_statistics.sh
LIVE_PROGRESS=1 bash scripts/run_0493x13c_C_longitudinal_statistics.sh
```

Both runners default to preserving completed work. To restart a branch from scratch, explicitly set `CLEAN_ROOT=1`.

## Default campaign size

- Hgamma: 40 simulations (5 gamma x 2 wavelengths x 4 seeds), about 4.195e9 particle-steps.
- Cstat: 132 simulations (24 A1 + 60 G08 + 48 G10), about 0.838e9 particle-steps total.
- Cstat particle-step budget is approximately equal by fluid (~0.279e9 each) because `gamma*Nrep=240`.

The many Cstat sub-runs are intentionally small and restartable. The branch-level `CAMPAIGN COMPLETE` marker is written only after all groups have been traversed and the analysis has succeeded.
