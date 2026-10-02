# 0493x21i — capillary-wave validation at sigma = 1000

Purpose: test the qualified particle/field free-surface closure one decade below the article calibration value (`sigmaDeclared=10000`) without modifying the solver, the physical chain, the fit protocol, or the qualification thresholds.

## Scientific design

Only `surfaceTensionSigma` changes:

- reference article calibration: `sigmaDeclared = 10000`;
- x21i validation: `sigmaDeclared = 1000`.

The nominal article fluid is unchanged:

- `Nx x Ny = 256 x 128`, `Lx x Ly = 1 x 0.5`, `h = 1/256`;
- `gamma = 8`, `dt = 0.0063471328149122585`;
- `kBT = 0.125`, liquid particle mass `m = 1`;
- `rhoRef = 524288`;
- `alphaSRC = 120 deg`;
- `nu_eff = 5.1019788e-4`;
- mean depth `H = 0.25`;
- initial amplitude `a = 2 h`;
- `surfaceTensionMinRadiusCells = 4`;
- qualified x13h kinetic/free-surface chain;
- `projectionMomentumCorrection=false` and `q6ForceProjectionMode=prestream_single_fused` exactly as in x21f/x21g.

No amplitude increase is made in the first test.  This makes the sigma=1000 campaign a clean one-parameter comparison.  If the low-sigma run fails only because the thermal signal-to-noise ratio becomes insufficient, that should be diagnosed before changing the amplitude.

## Expected theoretical frequencies

Finite-depth dispersion:

`omega^2 = (sigma/rho) k^3 tanh(k H)`.

For `sigma=1000`:

| mode | omega_theory | T_theory | 2-period steps | cells/lambda | a/lambda |
|---|---:|---:|---:|---:|---:|
| n=2 | 1.94186403 | 3.23564638 | 1020 | 128.0 | 0.015625 |
| n=3 | 3.57381180 | 1.75811869 | 554 | 85.33 | 0.0234375 |
| n=4 | 5.50266807 | 1.14184342 | 360 | 64.0 | 0.03125 |

The theoretical frequencies are exactly `1/sqrt(10)` of the corresponding `sigma=10000` values.

## Staged execution

The runner first computes the three `n=3` realizations with seeds:

- 4932501
- 4933501
- 4934501

The unchanged x12cal analyzer ensemble-averages the signed Fourier traces before fitting.  If and only if the `n=3` ensemble status is `PASS`, the runner automatically computes `n=2` and `n=4` with the same seeds and performs the global three-mode calibration.

This prevents wasting the longer `n=2` calculations if the one-decade lower surface tension is already limited by thermal interface noise at the representative intermediate mode.

The global PASS rule is unchanged:

- all requested mode ensembles PASS;
- mean fit R2 >= 0.98;
- relative standard deviation of `G_sigma` between modes <= 0.05.

No threshold is relaxed for sigma=1000.

## Restart policy

`RESTART=1` is the default.  Completed individual `(mode, seed)` realizations are identity-checked and reused.  An interrupted individual realization is rerun because these are small 256x128 calibrators; completed realizations are not recomputed.

The mass-field recorder remains active through x12cal.  The GUI is disabled to preserve comparability and avoid overhead on this small-grid calibration.

## Outputs

Pilot decision:

`runs/0493x21i_article_capillary_sigma1000_n3_ensemble/analysis/pilot_gate_0493x21i_sigma1000_n3_3seeds.txt`

If the pilot passes, global decision:

`runs/0493x21i_article_capillary_sigma1000_n234_ensemble/analysis/global_gate_0493x21i_sigma1000_n234_3seeds.txt`

and the unchanged x12cal CSVs in the same `analysis/` directory.

If the sigma=10000 x21g global CSV is still present, a non-gating comparison is also written to:

`cross_sigma_comparison_0493x21i.txt`.
