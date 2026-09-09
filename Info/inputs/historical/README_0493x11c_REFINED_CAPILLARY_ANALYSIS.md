# 0493x11c — refined quantitative capillary analysis

This is an **analysis/protocol correction only**.  It does not change CUDA
physics, x10q retention, Q6-G-F, surface tension, or the capillary-wave runs.

## A. Young–Laplace: paired sigma=0 subtraction

The solved x9e pressure diagnostic contains a large Q6 gauge/background.  Do
not force the absolute pressure level through the origin.

Run only the missing sigma=0 baselines:

```bash
bash scripts/run_0493x11a_young_laplace_sigma0_baselines.sh
```

Defaults: R/h = 8,12,20,40; seeds = 4931101,4931102,4931103; 1000 steps.
Existing positive-sigma runs are not deleted or rerun.

The runner automatically executes:

```bash
python3 scripts/analyze_0493x11a_young_laplace_paired.py \
  --active-manifest runs/0493x11a_young_laplace/manifest.csv \
  --baseline-manifest runs/0493x11a_young_laplace_sigma0/manifest.csv \
  --output-dir runs/0493x11a_young_laplace/analysis_refined
```

Primary relation:

    p(sigma)-p(0) = sigma * <kappa>_active.

Secondary relation:

    p(sigma)-p(0) = sigma / R_eff.

## B. Capillary waves: early/high-SNR refit

No simulation rerun is needed for the current six wave cases.

```bash
python3 scripts/analyze_0493x11b_capillary_wave_earlyfit.py \
  --cases-csv runs/0493x11b_capillary_wave/analysis/capillary_wave_cases.csv \
  --output-dir runs/0493x11b_capillary_wave/analysis/refined
```

The primary frequency fit is performed on the first **one theoretical period**
(fixed before looking at the answer), with sensitivity reported for
0.75, 1.00, and 1.25 periods.  The late part of the trace is used only to
estimate the thermal noise floor.

When 3-seed runs are added later, the same analyzer automatically reports
seed mean/std by (sigma, mode).
