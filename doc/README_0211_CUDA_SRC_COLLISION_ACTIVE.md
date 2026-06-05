# 0211 — Active CUDA SRC collision path

## Purpose

This patch promotes the CUDA SRC rotation kernel validated in 0209/0210 to an **active** runtime path in the real SRC/MPCD step.

The default remains the CPU/OpenMP collision.  The CUDA collision is used only when explicitly enabled:

```bash
MPCD_CUDA_SRC_COLLISION_USE=1
```

The active path applies the same per-particle SRC rotation as the CPU path:

```text
v_i <- u_cell + R_cell (v_i - u_cell)
```

where `cellId`, `cellUx`, `cellUy`, `cosA`, and `sinA` are still computed by the existing CPU step.  This patch does **not** introduce persistent GPU particle state; particle velocities are uploaded/downloaded inside the CUDA collision call.

## Scope

Included:

- active CUDA SRC collision in `src_collision_step` under `MPCD_CUDA_SRC_COLLISION_USE=1`;
- CPU path unchanged by default;
- shadow mode remains available when active mode is disabled;
- per-run active collision timing CSV;
- validation harness comparing CPU collision baseline to CUDA active collision.

Excluded:

- persistent GPU particle state;
- GPU generation of rotation signs;
- GPU cell-moment producer/consumer fusion;
- active use in non-TG production cases without validation.

## Runtime controls

```bash
MPCD_CUDA_SRC_COLLISION_USE=1
MPCD_CUDA_SRC_COLLISION_THREADS_PER_BLOCK=256
MPCD_CUDA_SRC_COLLISION_ACTIVE_STRICT=1
```

Shadow mode remains:

```bash
MPCD_CUDA_SRC_COLLISION_SHADOW=1
```

If active mode is enabled, shadow mode is intentionally ignored for the same step to avoid double validation/rotation ambiguity.

## Build

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
bash scripts/build_src_mpcd_cuda_0211.sh
```

## Validation

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
GRID_CASES='64:200 128:100' \
PROJECTION_BACKEND=cpu \
bash scripts/run_cuda_src_collision_active_0211.sh
```

Consolidated output:

```text
dev_history/artifacts/gpu_cuda_collision_0211/cuda_src_collision_active_0211.csv
```

Per-run active timing output:

```text
runs/cuda_src_collision_active_0211_<grid>/tg_periodic_full/cuda_src_collision_active_0211.csv
```

## Acceptance criteria

```text
verdict = PASS
failed_metrics = 0
invalidCellParticles = 0
```

The 0162 comparison should remain within the established tolerances.

## Next step

If 0211 is validated, the next performance-oriented step should not keep adding isolated upload/download kernels.  The logical next patch is a persistent GPU particle state shared by:

```text
cell-moment deposit -> SRC collision -> thermostat
```

This is required to avoid repeatedly uploading/downloading `x/y/vx/vy/role/mass/cellId` for each GPU sub-step.
