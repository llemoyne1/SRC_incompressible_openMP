# GPU patch 0327b — resize host cellId without sentinel fill

## Purpose

Patch 0327 tried to remove the host-side `cellIdOut.assign(n, -1)` cost in the strict SRC classic CUDA resident fast-diagnostics path by clearing `cellIdOut`.
That was too aggressive: the legacy CPU thermostat wrapper still checks `cellId.size()==Nactive` before consuming the GPU thermostat diagnostics, so the run failed at step 1 with:

```text
Fatal error: Thermostat cellId array has wrong active-particle size
```

Patch 0327b keeps the optimization idea but preserves the size contract:

```cpp
cellIdOut.resize(n);
```

instead of:

```cpp
cellIdOut.clear();
```

and instead of the original:

```cpp
cellIdOut.assign(n, -1);
```

In strict classic resident mode the active-particle count is stable, so after the first step `resize(n)` should not refill the array every step.

## Scope

The optimization remains guarded by:

```text
residentClassicMode0315f
FAST_THERMOSTAT_DIAG_0321
MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_HOST_CELLID_FILL_0327=1
```

Hybrid Q6/resampling/virial paths should keep their conservative host workspaces because they run with `srcClassicCudaModeEnable=false` and are validated separately by 0326d.

## Expected effect

The run should no longer fail with a thermostat cellId size error.
The measured target remains:

```text
srcPersistentDownload_s
src_collision
elapsed_s
```

The expected gain is modest; 0327b is valid only if it keeps `exitCode=0` and lowers or at least does not worsen the clean 0322/0325b baseline.
