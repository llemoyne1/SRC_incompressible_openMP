# 0207 — Active CUDA cell-relative thermostat

This patch turns the validated CUDA cell-relative thermostat into an active
runtime path, still isolated from the rest of the GPU work.

## Runtime flag

```bash
MPCD_CUDA_THERMOSTAT_USE=1
```

When enabled, the CPU path still computes the cell moments (`cellCount`,
`cellUx`, `cellUy`) exactly as before. The kinetic-energy accumulation,
cell scale computation, and velocity rescale are then delegated to the CUDA
thermostat primitive validated in 0205/0206.

The default remains CPU:

```bash
MPCD_CUDA_THERMOSTAT_USE=0
```

Active mode has priority over shadow mode. If both are requested, the active
thermostat drives the dynamics and shadow validation is disabled for that step.

## Validation harness

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
GRID_CASES='64:200 128:100' \
PROJECTION_BACKEND=cpu \
bash scripts/run_cuda_cell_thermostat_active_0207.sh
```

The harness compares:

- CPU baseline thermostat;
- active CUDA thermostat.

The main output is:

```text
dev_history/artifacts/gpu_cuda_thermostat_0207/cuda_cell_thermostat_active_0207.csv
```

Per-run active diagnostics are written inside each run directory as:

```text
cuda_cell_thermostat_active_0207.csv
```

## Expected status

The patch is still conservative: it does not keep particle arrays resident on
GPU between stages. Therefore the timing may still be dominated by uploads and
downloads. The purpose is to establish whether the active thermostat remains
physically identical and whether it is already neutral or beneficial once used
inside the real step.
