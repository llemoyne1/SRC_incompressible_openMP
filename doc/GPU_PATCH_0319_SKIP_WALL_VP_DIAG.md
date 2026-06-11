# GPU patch 0319 — skip CPU wall virtual-particle diagnostic in CUDA persistent collision

## Objective

Patch 0318b validated the wall+circle resident path:

- `wall_simple_0246` is active in `force_stream`.
- `immersed_circle_0284` no longer uploads the host particle state each step.
- SRC periodic runtime dropped from about 76.9 s to about 50.45 s for 10000 steps.

The remaining dominant phase is now `src_collision`:

- `src_collision` ≈ 35.94 s / 10000 steps.
- CUDA persistent collision/thermostat CSV accounts for ≈ 19.38 s.
- The residual ≈ 16.56 s is in the host envelope after the CUDA persistent collision.

Code inspection shows that after the CUDA persistent collision returns, the path calls
`populate_cuda_persistent_wall_virtual_diagnostics_0253(...)`, which reconstructs wall
virtual-particle diagnostic quantities on the CPU. The CUDA backend has already applied
the physical virtual-wall/circle contribution; this reconstruction only feeds
`runtime_summary.csv` columns such as `virtualParticleCount`, `virtualMass*` and
`virtualMomentum*`.

## Change

A runtime flag is added:

```bash
MPCD_CUDA_PERSISTENT_SRC_COLLISION_SKIP_WALL_VP_DIAG_0319=1
```

When enabled, `populate_cuda_persistent_wall_virtual_diagnostics_0253(...)` returns
immediately. Particle dynamics are unchanged; only the runtime summary virtual-particle
diagnostic columns are no longer reconstructed on the CPU for this CUDA persistent path.

The VK runner enables it by default through:

```bash
SRC_GPU_SKIP_WALL_VP_DIAG_0319=${SRC_GPU_SKIP_WALL_VP_DIAG_0319:-1}
```

Set `SRC_GPU_SKIP_WALL_VP_DIAG_0319=0` to restore the legacy diagnostic.

## Validation target

After rebuild, run the 0317d profiler again on the periodic VK case. Expected outcome:

- `src_collision` should decrease substantially from ≈ 35.94 s.
- The gap `src_collision - srcPersistentTotal` should shrink.
- `virtualParticleCount`, `virtualMass*`, `virtualMomentum*` columns in
  `summary_runtime.csv` are expected to be zero or stale/default in this benchmark mode.

## Important limitation

This is intentionally limited to the CUDA persistent collision diagnostic envelope. It
does not change Q6, resampling, virial, closed-capacity, or inlet/outlet logic.
