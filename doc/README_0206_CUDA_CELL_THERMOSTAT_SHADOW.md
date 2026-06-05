# 0206 — CUDA cell-relative thermostat shadow validation

This patch integrates the standalone CUDA cell-relative thermostat primitive from
0205 into the real SRC/MPCD time step in a **shadow-only** mode.

The production dynamics remain unchanged:

- the CPU/OpenMP cell-relative thermostat is still applied to the simulation
  state;
- when `MPCD_CUDA_THERMOSTAT_SHADOW=1`, the pre-thermostat state is copied,
  the CUDA thermostat is applied to that copy using the CPU-computed cell
  moments, and the CUDA result is compared against the CPU post-thermostat
  state;
- mismatches are recorded in `cuda_cell_thermostat_shadow_0206.csv` under each
  run directory.

The intent is to validate the thermostat in the actual step context before any
active replacement is attempted.

## Build

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
  bash scripts/build_src_mpcd_cuda_0206.sh
```

This build enables:

- `MPCD_ENABLE_CUDA_Q6`
- `MPCD_ENABLE_CUDA_CELL_MOMENTS`
- `MPCD_ENABLE_CUDA_THERMOSTAT`

## Validation

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
GRID_CASES='64:200 128:100' \
PROJECTION_BACKEND=cpu \
bash scripts/run_cuda_cell_thermostat_shadow_0206.sh
```

The harness writes:

```text
dev_history/artifacts/gpu_cuda_thermostat_0206/cuda_cell_thermostat_shadow_0206.csv
```

and per-run files:

```text
runs/cuda_cell_thermostat_shadow_0206_<grid>/tg_periodic_full/cuda_cell_thermostat_shadow_0206.csv
```

## Runtime flags

```text
MPCD_CUDA_THERMOSTAT_SHADOW=1
MPCD_CUDA_THERMOSTAT_SHADOW_EVERY=1
MPCD_CUDA_THERMOSTAT_SHADOW_TOL=1e-10
MPCD_CUDA_THERMOSTAT_SHADOW_DIAG_TOL=1e-10
MPCD_CUDA_THERMOSTAT_THREADS_PER_BLOCK=256
```

The shadow path is strict by default. A mismatch in velocity or diagnostics
throws an error unless `MPCD_CUDA_THERMOSTAT_SHADOW_STRICT=0` is set.

## Expected criteria

- `failed_metrics = 0` in the baseline/shadow comparison;
- `velocityMismatches = 0`;
- `maxAbsVx`, `maxAbsVy`, and `maxDiagDiff` near round-off;
- CPU and CUDA thermostat diagnostics agree for `cellsRescaled`,
  `particlesRescaled`, `kBTBefore`, `kBTAfter`, and scale extrema.

If this passes, the next patch can add an active CUDA thermostat mode guarded by
an explicit runtime flag.
