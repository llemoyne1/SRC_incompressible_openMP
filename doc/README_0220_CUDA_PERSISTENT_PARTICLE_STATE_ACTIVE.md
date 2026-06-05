# 0220 — Active persistent CUDA particle state in the real SRC+thermostat substep

This patch connects the `CudaParticleState` manager introduced in 0218 and
validated through the bridge validator in 0219 to the real `src_collision_step`.

The default CPU/OpenMP path is unchanged. The new shared-state path is enabled
only when both flags are set:

```bash
MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE=1
MPCD_CUDA_PERSISTENT_PARTICLE_STATE_USE=1
```

The supported subset is intentionally the same as 0215:

- periodic x and periodic y;
- full fluid domain;
- no wall virtual particles;
- no immersed solid;
- `projectionEnable=false`;
- no virial/capacity velocity kick between collision and thermostat;
- `thermostatMode=cell_relative_rescale`.

## What changes compared with 0215

0215 called the persistent CUDA SRC+thermostat substep with host particle arrays,
so the substep allocated and uploaded its own particle buffers internally.

0220 optionally uploads the particles into a thread-local `CudaParticleState`,
then calls the shared-state overload validated by 0219. This means the device
allocation can be reused across collision steps. The current host step still
uploads particle arrays each call because transport, Q6, resampling and other
operations remain CPU-authoritative; this patch is therefore an integration
step, not the final zero-copy GPU-resident path.

The per-run diagnostic file remains:

```text
<run>/<case>/cuda_persistent_src_collision_thermostat_0215.csv
```

but it now includes additional columns:

```text
sharedParticleStateEnabled
particleStateAllocateSeconds
particleStateUploadSeconds
particleStateAllocationCalls
particleStateReusedAllocation
```

## Validation

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
GRID_CASES='64:200 128:100' \
PROJECTION_ENABLE=false \
bash scripts/run_cuda_persistent_particle_state_active_0220.sh
```

The harness compares:

- CPU baseline;
- legacy internal-upload persistent SRC+thermostat;
- shared `CudaParticleState` persistent SRC+thermostat.

Expected criteria:

- `verdict=PASS`;
- `failed_metrics=0`;
- `sharedParticleStateFraction=1` in shared mode;
- allocation reuse after the first call.
