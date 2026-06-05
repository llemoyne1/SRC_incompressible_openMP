# 0205 — CUDA cell-relative thermostat standalone validator

This patch starts the CUDA thermostat work without changing the production
SRC/MPCD step.

## Scope

Added files:

- `include/cuda_cell_thermostat.h`
- `src/cuda_cell_thermostat.cu`
- `src/main_validate_cuda_cell_thermostat_0205.cpp`
- `scripts/build_cuda_cell_thermostat_0205.sh`
- `scripts/run_cuda_cell_thermostat_smoke_0205.sh`

The CPU/OpenMP simulation path is unchanged. No runtime flag is added to the
main step yet.

## Numerical contract

The CUDA primitive receives already computed real-particle cell moments:

- `cellId[i]`
- `cellCount[c]`
- `cellUx[c]`
- `cellUy[c]`

It then performs the mass-aware cell-relative rescale thermostat:

1. compute relative kinetic energy per cell on CUDA;
2. compute the cell rescale factor;
3. apply `v <- u_cell + scale * (v-u_cell)` to fluid particles;
4. return diagnostics matching `ThermostatDiagnostics`.

This mirrors the CPU function `apply_cell_relative_rescale_thermostat` while
isolating the thermostat stage from deposit/collision/resampling.

## Validation

```bash
cd /mnt/e/SRC_MPCD_dev/SRC_GPU

CUDA_ARCH_FLAGS='-arch=sm_89' \
GRID_CASES='64:64:20 128:128:20' \
bash scripts/run_cuda_cell_thermostat_smoke_0205.sh
```

Expected output:

```text
CUDA_CELL_THERMOSTAT_0205 PASS ...
```

Main CSV:

```text
dev_history/artifacts/gpu_cuda_thermostat_0205/cuda_cell_thermostat_smoke_0205.csv
```

Acceptance criteria:

- `verdict=PASS` for all cases;
- `velocityMismatches=0`;
- `maxAbsVx <= 1e-10`;
- `maxAbsVy <= 1e-10`;
- `maxDiagDiff <= 1e-10`.

## Next step

If this standalone validator passes, the next patch should add a shadow mode in
the real step, analogous to the 0200 CUDA cell-moment shadow path. The shadow
mode should compare post-thermostat velocities on real TG states without changing
the dynamics used for the validated output.
