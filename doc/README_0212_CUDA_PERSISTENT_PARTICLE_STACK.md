# 0212 — CUDA persistent particle stack prototype

This patch starts the transition from isolated CUDA kernels to a persistent GPU
particle state. It does **not** modify the production SRC/MPCD step yet.

The validated CUDA path is standalone and restricted to the periodic
Taylor--Green-like subset:

```text
upload particle SoA once
  x, y, vx, vy, mass, role
run several cycles fully on GPU:
  particle -> cell deposit
  cell mean velocity finalization
  SRC rotation
  cell-relative thermostat
final download of vx, vy only
```

This is deliberately different from the previous active paths, where deposit,
collision and thermostat each uploaded and downloaded their own arrays. The goal
is to validate that a shared device-resident particle state can carry several
successive kernels without intermediate host transfers.

## Files

```text
include/cuda_persistent_mpcd_step.h
src/cuda_persistent_mpcd_step.cu
src/main_validate_cuda_persistent_mpcd_step_0212.cpp
scripts/build_cuda_persistent_mpcd_step_0212.sh
scripts/run_cuda_persistent_mpcd_step_smoke_0212.sh
doc/README_0212_CUDA_PERSISTENT_PARTICLE_STACK.md
dev_history/artifacts/gpu_cuda_persistent_0212/*.csv
```

## Build

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
  bash scripts/build_cuda_persistent_mpcd_step_0212.sh
```

## Smoke validation

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
GRID_CASES='64:64:20 128:128:20' \
CYCLES=5 \
bash scripts/run_cuda_persistent_mpcd_step_smoke_0212.sh
```

The expected verdict is `PASS` for every case, with zero velocity mismatches.
The output CSV is:

```text
dev_history/artifacts/gpu_cuda_persistent_0212/cuda_persistent_mpcd_step_smoke_0212.csv
```

## Interpretation

A passing 0212 validates the first device-resident chain:

```text
deposit -> SRC collision -> thermostat
```

with only one host-to-device upload at the beginning and one device-to-host
velocity download at the end. This is the missing architectural step before
trying to replace the per-kernel upload/download active modes in the real
simulation step.

## Limitations

The prototype is intentionally limited:

```text
periodic x/y only;
no wall virtual particles;
no immersed solid;
no resampling on GPU;
no transport on GPU;
no Q6 coupling inside this persistent chain yet.
```

The next step should be an in-step shadow/active path that uses the same
persistent device state across the already validated deposit, SRC collision and
thermostat stages.
