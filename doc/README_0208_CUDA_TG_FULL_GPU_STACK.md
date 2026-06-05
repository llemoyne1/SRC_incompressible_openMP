# Patch 0208 — Combined CUDA TG stack validation

This patch adds a validation harness for the current CUDA stack on the periodic
Taylor--Green case. It does **not** add a new numerical kernel. It composes the
three CUDA blocks validated independently so far:

- CUDA Q6 periodic projection, with the batched device-side CG path;
- CUDA active particle-to-cell moments deposit;
- CUDA active cell-relative thermostat.

The CPU/OpenMP path remains the reference and the default. CUDA paths are enabled
only through runtime environment flags inside the harness.

## Modes

`run_cuda_tg_full_gpu_stack_0208.sh` supports:

- `cpu_baseline`: CPU deposit + CPU thermostat + CPU Q6;
- `cell_cuda`: CUDA cell moments only;
- `thermostat_cuda`: CUDA thermostat only;
- `cell_thermostat_cuda`: CUDA cell moments + CUDA thermostat;
- `q6_cuda`: CUDA Q6 only;
- `q6_cell_cuda`: CUDA Q6 + CUDA cell moments;
- `q6_thermostat_cuda`: CUDA Q6 + CUDA thermostat;
- `full_cuda`: CUDA cell moments + CUDA thermostat + CUDA Q6.

The default mode set is intentionally limited to:

```bash
cpu_baseline cell_cuda thermostat_cuda cell_thermostat_cuda q6_cuda full_cuda
```

Set `MODES` to run a fuller factorial sweep.

## Recommended validation

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
GRID_CASES='64:200 128:100' \
BATCH_SIZE=20 \
bash scripts/run_cuda_tg_full_gpu_stack_0208.sh
```

For a shorter smoke:

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
GRID_CASES='64:200' \
MODES='cpu_baseline cell_cuda thermostat_cuda full_cuda' \
bash scripts/run_cuda_tg_full_gpu_stack_0208.sh
```

The consolidated output is:

```text
dev_history/artifacts/gpu_cuda_combined_0208/cuda_tg_full_gpu_stack_0208.csv
```

## Acceptance criteria

- `failed_metrics = 0` for all enabled modes;
- `q6DivAfterProjectedFluxRms <= 1e-8` for Q6 CUDA modes;
- the full CUDA stack must not introduce physical drift relative to the CPU
  baseline;
- wall-time comparisons are informative but should be interpreted cautiously on
  short runs.

## Notes

This harness is meant to decide whether the three validated CUDA pieces compose
constructively. If `full_cuda` improves wall time on 128x128, the next numerical
kernel candidate should be either collision or a more resident particle/device
state. If `full_cuda` regresses, the thermostat transfer overhead should be
optimized before adding another active GPU stage.
