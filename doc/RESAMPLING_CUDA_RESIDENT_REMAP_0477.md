# 0477 - Shared-state resident remap and thermal stage

## Change

0477 removes the private CUDA particle state previously allocated by the 0448
remap/thermal backend. The backend now:

1. reuses the process-wide shared `CudaParticleState`;
2. skips the particle upload when that state is fresh;
3. applies the existing mass-remap and thermal kernels without changing their
   equations;
4. downloads only active-prefix `mass`, `vx`, and `vy`, which are still needed
   by the CPU post-remap deposit;
5. keeps the shared state marked fresh because the host mirror and device state
   are synchronized after the targeted download.

No new runtime selector was added. When the 0448 CUDA backend is selected, the
shared-state optimization is automatic. The existing CPU fallback remains
active when the CUDA backend does not handle the requested physics, including
the current mass-guard case.

The remap still consumes the general CPU-produced `cellId`, wet-cell mask,
cell mass, count and mean velocity arrays. Therefore 0477 does not introduce a
new boundary-condition or solid-geometry interpretation. This is a
compatibility property, not yet a validation of every boundary-condition
combination.

## Validation

Binary:

```text
build/src_mpcd_base_cuda_q6_resident_periodic_equiv_0477
```

The 200-step `128x128x40` comparison passed for both paths:

| mode | CPU wall s | CUDA wall s | CPU/CUDA | max summary delta |
| --- | ---: | ---: | ---: | ---: |
| src-resampling | 20.550 | 19.262 | 1.067 | 3.297e-12 |
| src-q6-resampling | 24.772 | 23.859 | 1.038 | 1.478e-12 |

For every one of the 200 remap calls in each CUDA run:

```text
remapSharedState = 1
remapUploadSkipped = 1
remapStateUploadSeconds = 0
```

## Three-size scaling

Configuration: 100 steps, gamma 40, seed 1628638.

| grid | mode | CPU wall s | CUDA wall s | CPU/CUDA | max summary delta |
| --- | --- | ---: | ---: | ---: | ---: |
| 64x64 | src-resampling | 3.808 | 2.794 | 1.363 | 2.910e-11 |
| 64x64 | src-q6-resampling | 3.697 | 3.857 | 0.959 | 2.359e-13 |
| 96x96 | src-resampling | 5.185 | 5.053 | 1.026 | 5.821e-11 |
| 96x96 | src-q6-resampling | 7.112 | 7.054 | 1.008 | 5.821e-11 |
| 128x128 | src-resampling | 8.568 | 8.156 | 1.051 | 9.681e-13 |
| 128x128 | src-q6-resampling | 12.453 | 12.072 | 1.032 | 1.164e-10 |

All six rows pass the `1e-9` comparison tolerance. Q6 remains slightly slower
than CPU on the smallest grid, where fixed launch and synchronization costs are
not amortized.

## Remaining costs and next validated step

The CUDA kernels themselves are no longer the main remap cost. At `128x128`,
100 targeted downloads cost about 0.16-0.19 s, while remap and thermal kernels
together cost about 0.016-0.018 s. The profile also exposes the CPU
`resampling_post_remap_deposit` as a remaining full particle pass.

The next structural step should therefore keep the post-remap deposit on the
shared CUDA state and download only the cell diagnostics required by the CPU
control plane. That change must be validated in this order:

1. periodic scaling and strict CPU/CUDA equivalence;
2. wall and inlet/outlet boundary cases;
3. `chi+Darcy/VP` solid cases;
4. population guard plus empty-refill;
5. mass guard, after its CUDA mutation and diagnostics are integrated.

Until stages 2-5 pass, unsupported combinations must retain the existing CPU
fallback rather than silently using the fast path.

Outputs:

```text
runs/0477_resident_remap_scaling/materializer_authoritative_report_0476.md
runs/0477_resident_remap_scaling_3sizes/materializer_authoritative_report_0476.md
```
