# 0150 — momentum diagnostics for closed-capacity MATLAB post-processing

This addendum updates:

```text
matlab/analyze_closed_capacity_inlet_only_0147.m
```

It adds momentum-oriented post-processing for runs produced by:

```bash
scripts/run_closed_capacity_inlet_only_0147.sh
```

The analyzer now reports and plots:

- total momentum `Px`, `Py`, and `|P|`;
- per-output-step momentum increments `Delta Px`, `Delta Py`;
- Q6 global momentum-correction estimate when only `q6MomentumCorrectionVx/Vy` is available;
- resampling momentum terms from extraction, insertion, remap and latent activation when present;
- optional inlet, wall, virial and thermostat impulse terms if future runtime summaries expose them;
- a partial momentum-budget residual

```text
Delta P_total - sum(available impulse terms)
```

The residual is intentionally labelled as partial because current 0147/0149 runtime CSV files do not yet export every physical impulse source, especially wall reaction and virial net impulse. Missing columns are kept as `NaN` and ignored in sums.

## New output figures

For each case, the script additionally writes:

```text
*_momentum_budget.png/.fig
*_resampling_momentum.png/.fig
```

For multi-case analysis, it also writes:

```text
comparison_momentum_0147.png/.fig
```

## New summary columns

The CSV summary now includes:

```text
finalMomentumX
finalMomentumY
finalMomentumMag
maxAbsMomentumX
maxAbsMomentumY
maxStepMomentumJump
maxAbsMomentumResidualX
maxAbsMomentumResidualY
```

## Usage

From the repository root:

```matlab
cd matlab
R = analyze_closed_capacity_inlet_only_0147( ...
    '../runs/closed_capacity_inlet_only_0147', ...
    'showFigures', true, ...
    'saveFigures', true);
```

## Interpretation notes

A strong drift in `Px` or `Py` should be compared with:

- the per-step jump `Delta P`;
- available Q6 correction estimates;
- resampling extraction/insertion/remap terms;
- future wall and virial impulse diagnostics when exported by the OpenMP runtime.

If the partial residual remains large, this does not necessarily mean the budget is wrong: it usually means one or more important impulse sources are not yet exported in `summary_runtime.csv`.
