# 0493x9c — passive curvature smoothing-support sweep

Purpose: qualify the curvature-only smoothing support before any surface-tension pressure jump is enabled.

## Physics status

This patch is **passive only**:
- no `sigma` parameter;
- no `phiGamma` modification;
- no Q6 RHS modification;
- no particle capillary kick;
- x6c physical `alpha` and x6f interface remain unchanged.

## Candidates evaluated in one simulation

All candidates use the same Scharr 3x3 normal/divergence operator introduced in x9b. Only the curvature-only `alphaK` smoothing support changes:

- pass 1: x9b reference, one binomial 3x3 pass;
- pass 2: two successive binomial 3x3 passes (effective 5x5 support);
- pass 3: three successive binomial 3x3 passes (effective 7x7 support).

x9c pass-2/pass-3 are computed only on summary/audit steps. The existing LiveVis `curvature` field continues to display the x9b one-pass field; x9c does not change LiveVis in this patch.

## Installation

Extract the bundle at the repository root, then:

```bash
python3 tools/apply_0493x9c_smoothing_sweep.py
git diff --check
bash scripts/build_src_mpcd_cuda_q6_resident_livevis_0486.sh
```

The apply script expects x9b + x9b-audit2 to already be installed. It is idempotent and does not enforce a clean Git working tree.

## Quick validation

Preflight only:

```bash
PREFLIGHT_ONLY=1 LIVE_VIS_ENABLE=0 LIVE_PROGRESS=1 \
bash scripts/run_0493x9c_ellipse_curvature.sh
```

Representative small circle, gamma 20:

```bash
GAMMA=20 R_CELLS=8 LIVE_VIS_ENABLE=0 LIVE_PROGRESS=1 \
bash scripts/run_0493x9c_ellipse_curvature.sh
```

The runner accepts either `RX`/`RY` or `R_CELLS`. When `R_CELLS` is set it creates a circle with `R = R_CELLS * h` and requires square cells.

## Full sweep

Default matrix:
- `GAMMA = 10 20 40`
- `R/h = 8 12 16 24 40 80`
- 18 physical one-step runs total;
- every run evaluates smoothing passes 1, 2 and 3 simultaneously.

Run:

```bash
LIVE_PROGRESS=1 bash scripts/run_0493x9c_curvature_sweep.sh
```

Override matrix if needed:

```bash
GAMMAS="10 20" R_CELLS_LIST="8 12 16" LIVE_PROGRESS=1 \
bash scripts/run_0493x9c_curvature_sweep.sh
```

The sweep disables LiveVis and filtered recording. By default it removes large `.smpcd` state files after each successful case (`KEEP_STATES=0`) while preserving CSV/JSON/log diagnostics. Set `KEEP_STATES=1` to retain them.

Main aggregate result:

```text
runs/0493x9c_curvature_sweep_400x400/curvature_sweep_0493x9c.csv
```

Each row reports gamma, radius in cells, smoothing pass count, mean curvature, standard deviation, maximum absolute curvature, relative mean bias, relative standard deviation and relative RMS error about `1/R`.

No numerical PASS threshold is imposed in x9c; the sweep is intended to identify the best noise/bias compromise and the minimum resolved radius for each gamma.
