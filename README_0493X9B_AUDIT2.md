# 0493x9b-audit2 — wall/interior curvature split

Diagnostic-only incremental patch on top of **0493x9b**.

It does **not** change:

- `alpha_x6c` or `alphaK_x9b`;
- x9a/x9b normals or curvature estimators;
- x6f/x6g, `phiGamma`, CG RHS, B1/RT0;
- particle velocities, resampling, virial, or LiveVis rendering.

The existing summary-cadence curvature face audit is split into three views:

- `all`: current x9a/x9b metrics;
- `interior`: both cells adjacent to the alpha=0.5 crossing are at least `wallMarginCells` from every **non-periodic** domain boundary;
- `nearWall`: complement of `interior`.

Periodic directions have no wall exclusion. The default margin is **8 cells** and can be changed only for diagnostics with:

```bash
CURVATURE_AUDIT_WALL_MARGIN_CELLS=8
```

The runner exports this as `MPCD_Q6_PHASE_CURVATURE_AUDIT_WALL_MARGIN_CELLS_0493X9B`.

## Files

- `tools/apply_0493x9b_audit2.py` — semantic incremental patch x9b -> x9b-audit2.
- `scripts/analyze_0493x9b_curvature_audit2.py` — stdlib-only analyzer.
- `0493x9b_audit2_review.diff` — review only; do not use `git apply`.

The existing `scripts/run_0493x9b_ellipse_curvature.sh` is modified semantically by the apply script.

## Apply and build

From `/mnt/e/SRC_MPCD_DEV/SRC_GPU-SURF` after extracting this bundle at repository root:

```bash
python3 tools/apply_0493x9b_audit2.py

git diff --check

bash scripts/build_src_mpcd_cuda_q6_resident_livevis_0486.sh
```

The apply script is idempotent and intentionally has no Git/working-tree guard.

## Recommended discriminating run

Re-run only the 30-degree quasi-plane first:

```bash
ANGLE_DEG=30 \
RX=100 \
RY=0.3125 \
STEPS=1 \
LIVE_VIS_ENABLE=0 \
LIVE_PROGRESS=1 \
bash scripts/run_0493x9b_ellipse_curvature.sh
```

The runner defaults to `CLEAN_RUN_ROOT=1`. Keep that default for this first audit run because x9b-audit2 extends the CSV schema; appending to a pre-audit CSV with `CLEAN_RUN_ROOT=0` would mix schemas.

Expected additional lines:

```text
[0493x9b-audit2] region=interior margin=8 ...
[0493x9b-audit2] region=nearWall margin=8 ...
```

Return the normal `[0493x9b-analysis]` line plus both audit2 region lines.

## Structural checks

The analyzer checks that:

```text
interiorCrossingFaces + nearWallCrossingFaces == crossingFaces
interiorValidCurvatureFaces + nearWallValidCurvatureFaces == validCurvatureFaces
```

for both x9a and x9b. No physical/accuracy threshold is introduced.
