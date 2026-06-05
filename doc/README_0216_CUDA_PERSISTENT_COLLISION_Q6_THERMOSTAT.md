# 0216 — Persistent CUDA collision + CUDA Q6 + CPU thermostat integration harness

This patch is a harness-only first step toward a fully persistent GPU path.
It does **not** introduce a new numerical kernel.

## Goal

The validated CUDA blocks are now:

- persistent CUDA particle-state deposit + SRC collision;
- CUDA Q6 projection for the periodic Taylor--Green subset;
- CUDA thermostat as a separate block.

Patch 0216 tests the conservative ordering

```text
persistent CUDA deposit/SRC collision
-> download to CPU workspace/state
-> CUDA Q6 projection through the existing Q6 backend
-> CPU thermostat through the original path
```

The CPU boundary between collision and Q6 is intentional.  This measures the
cost of the current boundary before attempting to keep projected velocities
resident on GPU.

## Modes

The script compares four modes:

```text
cpu_baseline                  CPU collision + CPU Q6 + CPU thermostat
q6_cuda                       CPU collision + CUDA Q6 + CPU thermostat
persistent_collision          persistent CUDA collision + CPU Q6 + CPU thermostat
persistent_collision_q6_cuda  persistent CUDA collision + CUDA Q6 + CPU thermostat
```

## Supported scope

The effective CUDA scope remains the same strict Taylor--Green subset:

- periodic x/y;
- full fluid domain;
- no immersed solid;
- no wall virtual particles;
- no open boundaries;
- Q6 CUDA only for periodic, unmasked grids.

## Run

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
GRID_CASES='64:200 128:100' \
BATCH_SIZE=20 \
bash scripts/run_cuda_persistent_collision_q6_thermostat_0216.sh
```

The consolidated CSV is written to

```text
dev_history/artifacts/gpu_cuda_persistent_0216/cuda_persistent_collision_q6_thermostat_0216.csv
```

## Validation criteria

For every non-baseline mode:

- `verdict = PASS`;
- `failed_metrics = 0`;
- `persistentInvalidCellParticles = 0` for persistent modes;
- `q6DivAfterProjectedFluxRms <= 1e-8` for Q6 CUDA modes.

## Interpretation

If `persistent_collision_q6_cuda` is correct but not faster, the next step is
not another isolated kernel.  The next step must reduce the CPU/GPU boundary
between persistent collision and Q6, or delay the download until after Q6 and
thermostat.
