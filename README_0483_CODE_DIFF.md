# 0483 code diff — resident remap-kernel fusion

This differential archive contains only the code diff currently present in the provided working tree:

- `patches/0483_remap_kernel_fusion.diff`

It changes only:

- `src/cuda_resampling_pipeline_shadow_0445.cu`

Intent:

- fuse target-energy accumulation and remap-mass application into one CUDA kernel;
- preserve the CPU physical order by reading `massBefore`, accumulating target energy with `massBefore`, then assigning `mass = massBefore * scale[c]`;
- reduce one kernel launch and one global-memory traversal in the remap/thermal stage.

Apply from repository root:

```bash
git apply patches/0483_remap_kernel_fusion.diff
```

Reverse from repository root:

```bash
git apply -R patches/0483_remap_kernel_fusion.diff
```

Build after applying:

```bash
OUT=build/src_mpcd_base_cuda_q6_resident_periodic_equiv_0483 \
CUDA_ARCH_FLAGS='-arch=sm_89' \
bash scripts/build_src_mpcd_cuda_q6_resident_0400.sh
```
