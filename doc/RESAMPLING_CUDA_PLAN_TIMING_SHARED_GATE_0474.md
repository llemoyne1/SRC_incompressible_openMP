# 0474 — CUDA plan timing + shared upstream gate

## Objective

Patch 0474 combines the next performance-oriented validation with a timing split aimed at the remaining non-resident resampling bottleneck.

After 0471–0473, the CUDA resampling commit path no longer pays the CPU rollback copy, per-step full upload, or active-prefix/full-state download. The remaining suspected bottleneck is the CPU-authoritative construction of the resampling workspace:

- particle-to-cell deposit,
- poor/rich classification,
- receiver/donor list construction,
- transfer-plan construction,
- donor-particle selection,
- passive extraction operation construction.

0474 keeps the 0473 fast commit path but enables a stricter upstream CUDA gate and internal timing profiles.

## Code change

0474 modifies `try_run_cuda_resampling_upstream_shadow_0450(...)` so the 0450/0451 upstream gate can reuse the process-local shared `CudaParticleState` when enabled by:

```bash
MPCD_CUDA_RESAMPLING_UPSTREAM_SHARED_STATE_0474=1
```

If the shared state is fresh, the upstream CUDA deposit/classification/planner gate skips the host-to-device upload. If it is not fresh, the gate uploads into the shared state and marks it fresh.

New columns are added to `cuda_resampling_upstream_shadow_0450.csv`:

```text
upstreamSharedState0474
upstreamUploadSkipped0474
uploadSeconds
```

## Validation mode

The 0474 runner enables:

```bash
MPCD_INTERNAL_PROFILES=1
MPCD_CUDA_RESAMPLING_DIRECT_STATE_COMMIT_0471=1
MPCD_CUDA_RESAMPLING_SHARED_STATE_DIRECT_COMMIT_0472=1
MPCD_CUDA_RESAMPLING_HOST_PATCHBACK_0473=1
MPCD_CUDA_RESAMPLING_UPSTREAM_SHARED_STATE_0474=1
MPCD_CUDA_RESAMPLING_UPSTREAM_SHADOW_0450=1
MPCD_CUDA_RESAMPLING_UPSTREAM_APPLY_0451=1
MPCD_CUDA_RESAMPLING_OPERATION_MATERIALIZE_0453=1
```

The upstream gate cadence is controlled by:

```bash
UPSTREAM_GATE_EVERY=${DEVICE_GATE_EVERY}
```

## Expected outputs

The runner produces:

```text
runs/0474_cuda_plan_timing_shared_gate/cuda_plan_timing_shared_gate_report_0474.md
runs/0474_cuda_plan_timing_shared_gate/cuda_plan_timing_shared_gate_summary_0474.csv
```

and reuses the 0464/0463 scaling report.

A successful run should show:

```text
PASS-like rows: 6/6
upstream rows/pass > 0
upstream shared/skip > 0
up max upload s = 0 when the shared state is fresh
materializer rows/pass/apply > 0
carrier max upload s = 0
carrier max state dl s = 0
```

The timing columns from `deposit_profile_0172.csv` expose the remaining CPU plan cost:

```text
post_guard_total_ms
transfer_plan_build_ms
donor_particle_selection_ms
passive_extraction_plan_ms
```

## Interpretation

0474 is not yet the full host-free planner. It is the transition patch that prevents the upstream CUDA validation gate from reintroducing an H2D upload and quantifies the remaining CPU-authoritative planning cost. If the report shows that `transfer_plan_build`, `donor_particle_selection`, or `passive_extraction_plan` dominate, the next patch should replace those stages with CUDA-authoritative buffers rather than further optimizing the host patchback path.
