# 0226 — Persistent particle+cell collision path combined with CUDA Q6

## Purpose

0225 validated the active `CudaParticleState + CudaCellWorkspace` path for the
periodic Taylor--Green subset with `projectionEnable=false`:

```text
CUDA deposit -> CUDA SRC collision -> CUDA cell-relative thermostat
```

0226 adds the collision-only shared-state bridge needed for the physical TG
incompressible order:

```text
CUDA deposit -> CUDA SRC collision
-> CUDA Q6 projection
-> CPU thermostat
```

The thermostat is deliberately left on CPU in this harness, because the
existing algorithm applies Q6 between SRC collision and thermostat. The earlier
persistent SRC+thermostat path remains valid only when `projectionEnable=false`.

## Code changes

The patch adds collision-only overloads of
`cuda_apply_persistent_tg_deposit_src_collision(...)` that accept:

```text
CudaParticleState
CudaParticleState + CudaCellWorkspace
```

and wires them into `src_collision_step` when:

```bash
MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=1
MPCD_CUDA_PERSISTENT_PARTICLE_STATE_USE=1
MPCD_CUDA_PERSISTENT_CELL_WORKSPACE_USE=1
```

Unlike `MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE=1`, this path is compatible
with `projectionEnable=true` because it performs only deposit+SRC collision.

## Build

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
  bash scripts/build_src_mpcd_cuda_0226.sh
```

## Validation

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
GRID_CASES='64:200 128:100' \
BATCH_SIZE=20 \
bash scripts/run_cuda_persistent_cell_workspace_q6_0226.sh
```

The main output is:

```text
dev_history/artifacts/gpu_cuda_persistent_0226/cuda_persistent_cell_workspace_q6_0226.csv
```

## Modes

The harness compares:

```text
cpu_baseline               : CPU collision + CPU Q6 + CPU thermostat
q6_cuda                    : CPU collision + CUDA Q6 + CPU thermostat
shared_collision           : shared GPU collision + CPU Q6 + CPU thermostat
shared_collision_q6_cuda   : shared GPU collision + CUDA Q6 + CPU thermostat
```

## Expected criteria

- `failed_metrics = 0` for all modes;
- `sharedParticleStateFraction = 1` for shared modes;
- `sharedCellWorkspaceFraction = 1` for shared modes;
- `invalidCellParticles = 0`;
- `q6DivAfterProjectedFluxRms <= 1e-8` for CUDA Q6 modes.

## Notes

This patch still restores the CPU workspace after the CUDA collision substep.
That is intentional: Q6, diagnostics, summaries, resampling and dumps remain
unchanged. The next performance step, if this harness passes, is to reduce the
CPU/GPU boundary around Q6 rather than stacking independent CUDA modules with
full transfers.
