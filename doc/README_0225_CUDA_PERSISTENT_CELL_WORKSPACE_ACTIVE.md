# 0225 — Active persistent CUDA particle + cell workspace path

## Scope

This patch wires the `CudaCellWorkspace` introduced in 0224 into the real
`src_collision_step` persistent CUDA SRC+thermostat path.  It is still limited
to the same conservative subset used by the previous persistent CUDA patches:

- periodic Taylor--Green style domains;
- no wall virtual particles;
- no immersed solid;
- `projectionEnable=false` for this path;
- active only when requested by environment variables.

The CPU/OpenMP path remains the default.

## New runtime flag

```bash
MPCD_CUDA_PERSISTENT_CELL_WORKSPACE_USE=1
```

This flag requires:

```bash
MPCD_CUDA_PERSISTENT_PARTICLE_STATE_USE=1
MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE=1
```

The resulting sub-step is:

```text
CudaParticleState upload/cached metadata
→ CudaCellWorkspace reused cell buffers
→ CUDA deposit
→ CUDA SRC collision
→ CUDA cell-relative thermostat
→ final download vx/vy + CPU workspace cell moments
```

The final CPU workspace restoration is intentionally kept so that the existing
summaries, diagnostics, resampling and downstream CPU stages remain unchanged.

## Build

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
  bash scripts/build_src_mpcd_cuda_0225.sh
```

## Validation

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
GRID_CASES='64:200 128:100' \
PROJECTION_ENABLE=false \
bash scripts/run_cuda_persistent_cell_workspace_active_0225.sh
```

The main output is:

```text
dev_history/artifacts/gpu_cuda_persistent_0225/cuda_persistent_cell_workspace_active_0225.csv
```

Expected criteria:

- all modes pass the 0162 comparison (`failed_metrics=0`);
- `shared_particle_cell_workspace` has `sharedParticleStateFraction=1`;
- `shared_particle_cell_workspace` has `sharedCellWorkspaceFraction=1`;
- `cellWorkspaceReusedAllocationFraction` is close to 1 after the first step;
- no invalid cell particles.

## Notes

This patch removes repeated cell-buffer allocation/ownership from the active
persistent path. It does not yet make the cell workspace CPU-free: full CPU
workspace restoration remains enabled for correctness and diagnostics. The next
major performance step is to reduce or delay the final CPU workspace download
when downstream stages do not need all cell fields immediately.
