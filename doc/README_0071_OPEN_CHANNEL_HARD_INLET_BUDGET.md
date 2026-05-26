# 0071 — Straight-channel hard-inlet/passive-outlet mass-budget test

This diagnostic run is designed to answer one narrow question before adding any outlet sponge/cap/control:

> With the current `hard_cell_density` inlet and passive outlet, can the code naturally relax toward a constant mass throughput in a straight channel, and does Q9 limit the density/mass transient?

No immersed obstacle is used in this test.

## Scope

This patch adds only run/analysis/visualization files. It does not change the C++ solver. It assumes the 0070 Q9 `ramp_floor` fix has already been applied.

Added files:

```text
scripts/run_open_channel_hard_inlet_budget_0071.sh
matlab/analyze_open_channel_hard_inlet_budget_0071.m
matlab/make_open_channel_hard_inlet_visual_report_0071.m
doc/README_0071_OPEN_CHANNEL_HARD_INLET_BUDGET.md
```

## Default case

The default run keeps the physical channel size and inlet speed of the backward-step tests, but reduces the grid:

```text
Lx = 2.0
Ly = 1.0
Nx = 48
Ny = 24
gamma = 20
dt = 0.001
Uin = 0.05
CASE_STEPS = 60000
```

The advective time is approximately

```text
Tadv = Lx / Uin = 40
```

so `60000` steps corresponds to `t = 60`, i.e. about `1.5 Tadv`.

The default cases are:

```text
openchan_q6_hard_inlet_48x24_long
openchan_q9_hard_inlet_s003_48x24_long
openchan_q9_virial_hard_inlet_s003_48x24_long
```

A classic case can be added with `RUN_CLASSIC=1`.

## Run

From the repository root:

```bash
RUN_ROOT=runs/open_channel_hard_inlet_budget_0071 \
CASE_STEPS=60000 \
SUMMARY_EVERY=250 \
DUMP_STATE_EVERY=5000 \
NUM_THREADS=8 \
AUTO_ANALYZE=1 \
./scripts/run_open_channel_hard_inlet_budget_0071.sh
```

For a fast smoke test:

```bash
RUN_ROOT=runs/open_channel_hard_inlet_budget_0071_smoke \
CASE_STEPS=1000 \
SUMMARY_EVERY=100 \
DUMP_STATE_EVERY=500 \
NUM_THREADS=8 \
AUTO_ANALYZE=1 \
./scripts/run_open_channel_hard_inlet_budget_0071.sh
```

## Manual analysis

```matlab
cd matlab
R = analyze_open_channel_hard_inlet_budget_0071('root','..', ...
    'runRoot','runs/open_channel_hard_inlet_budget_0071');
V = make_open_channel_hard_inlet_visual_report_0071('root','..', ...
    'runRoot','runs/open_channel_hard_inlet_budget_0071');
cd ..
```

The main summary file is:

```text
runs/open_channel_hard_inlet_budget_0071/analysis_0071/open_channel_hard_inlet_budget_summary_0071.csv
```

The analysis also writes runtime and state-budget time series under `analysis_0071/`, plus PNG plots.

## Main decision criteria

Inspect the late-time quantities:

```text
NpSlopeLate_perTime
NpSlopeLate_perStep
sampledBoundaryNetMeanLate
outletOverSourceMeanLate
stateOutletOverInletFluxProxyMeanLate
stdNLate
maxNLate
```

Interpretation:

- If `NpSlopeLate_perTime -> 0`, `sampledBoundaryNetMeanLate -> 0`, and `outletOverSourceMeanLate -> 1`, the hard inlet/passive outlet pair can naturally relax in a straight channel.
- If these quantities remain clearly positive/imbalanced, the issue exists even without the obstacle and should be treated as an outlet/boundary-coupling problem before returning to the backward-step case.
- If Q9 reduces `stdNLate`, `maxNLate`, or the late mass slope relative to Q6, then Q9 is limiting the transient. If Q9 leaves the global slope unchanged but changes local density statistics, it is redistributing the transient without fixing the open-boundary budget.

## Notes on the boundary counters

`summary_runtime.csv` reports boundary insertion/deletion counters at written summary rows. They are exact per written step, not cumulative over skipped steps unless `SUMMARY_EVERY=1`. The default `SUMMARY_EVERY=250` is intended for long-run trend analysis. For exact step-by-step boundary accounting on a shorter run, use:

```bash
SUMMARY_EVERY=1 CASE_STEPS=2000 ./scripts/run_open_channel_hard_inlet_budget_0071.sh
```
