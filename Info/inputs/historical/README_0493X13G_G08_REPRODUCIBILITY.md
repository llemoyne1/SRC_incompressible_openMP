# 0493x13g — G08 transverse reproducibility

Purpose: resolve the x13d/x13f discrepancy at the anchor `(alpha=120 deg, lambda/h=0.48)` and determine whether `(120 deg, 0.72)` has a reproducible viscosity advantage while keeping the 1.5x larger timestep.

No `src/` or `include/` modification.

## Design

Both candidates use gamma=8, alpha=120 deg, Ny=256, Nx=32, U0=0.05, thermostat and SRC settings identical to x13f.

Two variance tracks are run:

- `repeat_same`: 6 repeated executions of one byte-identical initial state generated with seed 4931411, with the same runtime seed 4931411. This measures execution/GPU reproducibility.
- `independent`: 7 new independent states/seeds 4931412..4931418. In analysis, `repeat_same/rep00` is reused as independent seed 4931411, giving 8 paired independent realizations per candidate without two redundant runs.

Candidates are interleaved in run order to reduce temporal drift.

The runner records `gitHead`, branch, binary SHA256, and an aggregate SHA256 of the current `src/` + `include/` file contents. The production runner aborts only if the binary itself changes during the campaign; it does not require a clean Git tree.

## Outputs

`runs/0493x13g_G08_reproducibility/analysis/`:

- `H_repro_runs_0493x13g.csv`: individual fits.
- `H_repro_group_summary_0493x13g.csv`: repeat and independent variance, ensemble-mean fit, final-dump hash count.
- `H_repro_pairs_0493x13g.csv`: paired 0.48 vs 0.72 comparisons.
- `H_repro_pair_summary_0493x13g.csv`: paired bootstrap CI and probability of positive viscosity reduction.
- `H_repro_decision_0493x13g.csv`: compact decision.
- `H_repro_historical_runs_0493x13g.csv`: x13d/x13f historical rows when those outputs are still present.

## Suggested execution

```bash
bash scripts/check_0493x13g_H_reproducibility.sh
PREFLIGHT_ONLY=1 bash scripts/run_0493x13g_H_reproducibility.sh
LIVE_PROGRESS=1 bash scripts/run_0493x13g_H_reproducibility.sh
```

The runner is restartable with `SKIP_EXISTING=1`.
