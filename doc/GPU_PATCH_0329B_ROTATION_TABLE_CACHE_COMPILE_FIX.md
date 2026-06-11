# GPU patch 0329b — rotation-table cache compile fix

0329b is a compile-only correction for the 0329 rotation-table cache patch.

The first 0329 archive declared `rotationTableCache0329` before `deviceRotationTables0272` in the collision-only overload of `cuda_apply_persistent_tg_deposit_src_collision(...)`, which produced:

```text
src/cuda_persistent_mpcd_step.cu(...): error: identifier "deviceRotationTables0272" is undefined
```

0329b moves the `rotationTableCache0329` guard below the `deviceRotationTables0272` declaration in that overload.  It does not change the intended runtime semantics:

- if `randomRotationSign=true`, only the constant cos(theta) table is cached and the step-dependent signed sin(theta) table is still regenerated;
- if `randomRotationSign=false`, both cos and sin tables may be reused after initialization;
- the feature remains opt-in through `MPCD_CUDA_PERSISTENT_SRC_COLLISION_ROTATION_TABLE_CACHE_0329=1`, enabled by the VK runner default `SRC_GPU_ROTATION_TABLE_CACHE_0329=1`.

No solver-path optimization beyond the original 0329 behavior is added here.
