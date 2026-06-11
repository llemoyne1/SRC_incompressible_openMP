# GPU patch 0329 — safe rotation-table cache

## Purpose

Patch 0329 targets the measured post-0327b kernel cost associated with
`setup_fill_rotation_tables_0272` in the classic resident CUDA SRC path.

The VK-like benchmark currently uses `randomRotationSign=true`, so the complete
`cosA/sinA` rotation table cannot be cached across steps without changing the
SRD random rotation sequence.  The patch therefore implements a conservative
split:

- cache `cos(theta)` on the device when the workspace/signature is unchanged;
- regenerate only `sin(theta)*sign(cell,step)` every step when
  `randomRotationSign=true`;
- reuse both `cos` and `sin` after first initialization when
  `randomRotationSign=false`.

The patch is disabled unless the explicit environment flag is enabled:

```bash
MPCD_CUDA_PERSISTENT_SRC_COLLISION_ROTATION_TABLE_CACHE_0329=1
```

The VK demo runner enables it by default through:

```bash
SRC_GPU_ROTATION_TABLE_CACHE_0329=1
```

Set `SRC_GPU_ROTATION_TABLE_CACHE_0329=0` to restore the 0322 full rotation-table
setup kernel.

## Scope

The shortcut is restricted to the strict classic resident CUDA path.  Hybrid
Q6/resampling/virial paths keep the conservative 0322 behavior because they run
with `srcClassicCudaModeEnable=false` and do not rely on the fused classic path.

No `.patch` file is provided; this archive contains modified files only.

## Expected effect

On the current VK-like benchmark with `randomRotationSign=true`, the expected
effect is modest: `setup_fill_rotation_tables_0272` should be replaced in the
0324/0328 microprofile by one first-step `setup_fill_rotation_cos_cache_0329`
row plus per-step `setup_fill_rotation_sin_0329` rows.  The main benchmark
should show a reduction in `srcPersistentKernel_s` if the original full setup
kernel was materially limited by the redundant `cosA` writes.

If the measured effect is neutral or negative, disable it with:

```bash
SRC_GPU_ROTATION_TABLE_CACHE_0329=0
```
