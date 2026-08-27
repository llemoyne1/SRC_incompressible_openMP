# 0493x13d-C fast-fit fix1

Scope: analysis tooling only. No `src/` or `include/` change and no new physical simulation.

## Cause of the slowdown
The original x13d analyzer called the full 0493w1 damped-cosine grid search for every bootstrap sample. The legacy search evaluates 18,160 `(omega,beta)` pairs, each with a 3-column least-squares solve. With 500 bootstraps × 6 groups this creates >54 million least-squares solves.

## Fix
For each physical group:
1. perform one unchanged legacy/global 0493w1 fit on the pooled signal;
2. validate that a compact local search reproduces the pooled result;
3. use that local search for individual replicates and bootstrap resamples;
4. if a local optimum touches the local window boundary, automatically fall back to the unchanged global search for that sample.

The local schedule is `21×17 + 17×13 + 13×11 = 721` candidate pairs, approximately 25× fewer than a legacy/global fit.

The estimator itself is unchanged:

`rho_k(t) = C + exp(-beta t) [A cos(omega t) + B sin(omega t)]`

`nu_L = 2 beta / k^2`

`c_s = sqrt(omega^2 + beta^2) / k`

## Validation
Run:

```bash
bash scripts/check_0493x13d_C_fastfit_fix1.sh
```

The check compares the fast local search to the unchanged global search on a synthetic mode and runs a 100-bootstrap timing smoke.

## Production analysis

```bash
BOOTSTRAP=500 \
VALIDATE_LOCAL=1 \
bash scripts/run_0493x13d_C_damped_analysis.sh
```

Existing x13c Cstat data are read only. Existing x13d CSVs with the same names are overwritten by the new analysis outputs.

New diagnostics include:
- `localValidation`
- `localVsGlobalCsRelative`
- `localVsGlobalNuLRelative`
- `bootstrapGlobalFallbackFraction`
- `analysisElapsedSeconds`
- `analysisMsPerBootstrap`
- `analysisFix=0493x13d-C-fastfit-fix1`
