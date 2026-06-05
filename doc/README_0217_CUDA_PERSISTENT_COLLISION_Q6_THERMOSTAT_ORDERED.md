# 0217 — Ordered persistent CUDA collision + Q6 + thermostat harness

Patch 0217 is a harness-only integration step.  It introduces no new numerical
kernel and does not change the default CPU/OpenMP path.

## Goal

Patch 0216 validated the conservative composition

```text
persistent CUDA deposit/SRC collision
-> download to CPU state/workspace
-> CUDA Q6 projection
-> CPU thermostat
```

Patch 0217 adds the algorithmically complete ordered stack with the existing
separate CUDA thermostat:

```text
persistent CUDA deposit/SRC collision
-> current CPU/GPU boundary before Q6
-> CUDA Q6 projection
-> current CPU/GPU boundary before thermostat
-> CUDA cell-relative thermostat
```

This deliberately preserves the current CPU/GPU boundaries.  The purpose is to
measure the full correct order before attempting the next, more intrusive step:
keeping the projected velocity state resident on GPU through Q6 and thermostat.

## Modes

The script compares:

```text
cpu_baseline                         CPU collision + CPU Q6 + CPU thermostat
q6_cuda                              CPU collision + CUDA Q6 + CPU thermostat
persistent_collision                 persistent CUDA collision + CPU Q6 + CPU thermostat
thermostat_cuda                      CPU collision + CPU Q6 + CUDA thermostat
persistent_collision_q6_cuda         persistent CUDA collision + CUDA Q6 + CPU thermostat
ordered_full_cuda                    persistent CUDA collision + CUDA Q6 + CUDA thermostat
```

`ordered_full_cuda` is not yet a fully resident GPU step.  It is the ordered
composition of the validated blocks with the present transfer boundaries still
in place.

## Supported scope

The effective CUDA scope remains the strict Taylor--Green subset:

- periodic x/y;
- full fluid domain;
- no open boundaries;
- no wall virtual particles;
- no immersed solid;
- Q6 CUDA only on periodic, unmasked grids.

## Run

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
GRID_CASES='64:200 128:100' \
BATCH_SIZE=20 \
bash scripts/run_cuda_persistent_collision_q6_thermostat_ordered_0217.sh
```

The consolidated CSV is written to

```text
dev_history/artifacts/gpu_cuda_persistent_0217/cuda_persistent_collision_q6_thermostat_ordered_0217.csv
```

## Validation criteria

For every non-baseline mode:

- `verdict = PASS`;
- `failed_metrics = 0`;
- `persistentInvalidCellParticles = 0` for persistent modes;
- `q6DivAfterProjectedFluxRms <= 1e-8` for Q6 CUDA modes;
- thermostat modes report finite `thermostatKBTAfterLast` close to the target.

## Interpretation

If `ordered_full_cuda` is correct but not faster, the next patch should not add
another separate CUDA block.  It should reduce the boundary between Q6 and the
thermostat, ideally by keeping the velocity state resident on GPU after Q6 and
applying the thermostat before downloading final velocities and CPU workspace
summaries.
