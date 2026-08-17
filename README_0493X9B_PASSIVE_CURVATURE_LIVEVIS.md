# 0493x9b — passive curvature candidate + resident LiveVis

## Scope

Incremental patch on top of 0493x9a. No surface tension is applied.

Physics contract unchanged:

- no `sigma` parameter;
- no modification of x6c physical `alpha`;
- no modification of x6f/x6g `phiGamma`;
- no RHS change;
- no B1/RT0 change;
- no particle capillary kick;
- resampling and virial remain off in the qualification runner.

x9a remains enabled as the baseline estimator.

## x9b estimator

A separate curvature-only field is built from the qualified x6c alpha:

```text
alpha_x6c
  -> one 3x3 binomial pass -> alpha_kappa
  -> Scharr 3x3 gradient -> outward normal n
  -> Scharr 3x3 divergence -> kappa_x9b
```

The physical interface used for the audit remains the original `alpha_x6c=0.5`
interface. Curvature is linearly interpolated to the same crossing position used
by x9a/x6f.

The originally considered direct Hessian formula was not retained: a
deterministic reproduction of the 400x400/gamma=20 runner showed that applying
it directly to the quantized x6c alpha amplified local noise. The selected x9b
candidate is still passive and uses a rotationally improved 3x3 stencil.

## LiveVis

New aliases:

```text
field = curvature
field = kappa
field = curvature_x9b
field = kappa_x9b
```

The field is resident-only. `cuda_live_field_0337` reads the x9b CUDA curvature
buffer directly. If the LiveVis grid differs from the Q6 grid, nearest-neighbour
resampling is used so the visualization itself does not smooth the field.

`particleTypeFilter` is ignored for curvature and there is no particle deposit.
If x9b curvature is unavailable, CPU density fallback is intentionally blocked
instead of displaying a misleading field.

The x9b runner uses its own control file under the run directory and defaults to:

```text
field = curvature
colormap = blue_red
clip = 10
smoothPasses = 0
liveGridNx = NX
liveGridNy = NY
```

Filtered recording is disabled by default.

## Install

From the repository root:

```bash
python3 tools/apply_0493x9b_passive_curvature_livevis.py
git diff --check
bash scripts/build_src_mpcd_cuda_q6_resident_livevis_0486.sh
```

The apply script is idempotent and imposes no clean-working-tree guard. It
requires the x9a source anchors to already be present.

## Preflight

```bash
PREFLIGHT_ONLY=1 LIVE_VIS_ENABLE=0 LIVE_PROGRESS=1 \
  bash scripts/run_0493x9b_ellipse_curvature.sh
```

## First CUDA comparison: circle R=0.3125

For a normal non-blocking qualification:

```bash
LIVE_PROGRESS=1 \
  bash scripts/run_0493x9b_ellipse_curvature.sh
```

To inspect the final curvature frame interactively:

```bash
LIVE_VIS_HOLD_ON_EXIT=1 LIVE_PROGRESS=1 \
  bash scripts/run_0493x9b_ellipse_curvature.sh
```

Expected analytic circle curvature is `1/R = 3.2`. The analyzer deliberately
sets no accuracy PASS threshold yet; it reports x9b/x9a ratios.

## Oblique quasi-plane

```bash
ANGLE_DEG=30 RX=100 RY=0.3125 STEPS=1 LIVE_PROGRESS=1 \
  bash scripts/run_0493x9b_ellipse_curvature.sh
```

The clipped ends at the closed-box walls can still create large extrema; the
mean/absolute-mean and comparison to x9a remain useful diagnostics.

## Outputs

```text
output/cuda_phase_curvature_0493x9a.csv
output/cuda_phase_curvature_0493x9b.csv
curvature_compare_0493x9b.json
```

The key console line is:

```text
[0493x9b-analysis] ... x9a[...] x9b[...] stdRatio=... absMeanRatio=...
```
