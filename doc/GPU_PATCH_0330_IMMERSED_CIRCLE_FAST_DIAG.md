# GPU patch 0330 — immersed circle fast diagnostics

## Purpose

After the validated 0327b checkpoint, the resident `immersed_circle_0284`
phase still costs about 1.35–1.40 s per 10000-step VK-like benchmark run,
including roughly 0.58–0.60 s in the `download_s` column. In the current
resident path `MPCD_CUDA_IMMERSED_CIRCLE_0284_DOWNLOAD_ALL=0`, this is not a
full particle download; it is mostly the per-step diagnostic hit counter path:

- allocate `dHits`,
- `cudaMemset(dHits)`,
- kernel atomic increments,
- copy one counter back to host,
- free `dHits`.

This patch adds a fast diagnostics mode that skips that diagnostic counter for
classic resident VK benchmarking.

## Runtime flag

Enabled by the VK runner by default:

```bash
MPCD_CUDA_IMMERSED_CIRCLE_FAST_DIAGNOSTICS_0330=1
```

The runner exposes:

```bash
SRC_GPU_IMMERSED_CIRCLE_FAST_DIAG_0330=0
```

to restore the legacy hit-counter path.

## Physics and diagnostics

The CUDA reflection kernel is still executed and still updates `x,y,vx,vy` on
the shared resident GPU particle state.  Only the `hits` diagnostic is skipped;
when fast diagnostics are enabled, `CudaImmersedCircle0284Diagnostics::hits`
will remain zero for this handler.

No Q6, resampling, virial, closed-capacity, or inlet/outlet path is changed by
this patch. The default runner change is limited to
`scripts/run_demo_src_classic_cuda_von_karman_cylinder_0285.sh`.

## Expected effect

Primary metric:

```text
immersed_circle_0284 download_s should drop substantially from ~0.58 s.
```

Secondary metrics:

```text
immersed_solid total_s should decrease.
elapsed_s should move toward the x2-vs-VKKH target.
```

If the run is neutral or regressive, disable with
`SRC_GPU_IMMERSED_CIRCLE_FAST_DIAG_0330=0` and roll the patch back.
