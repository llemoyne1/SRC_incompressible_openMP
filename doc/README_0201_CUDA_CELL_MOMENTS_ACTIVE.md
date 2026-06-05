# 0201 — CUDA active particle-to-cell moments deposit

## Purpose

Patch 0201 is the first active integration of the CUDA particle-to-cell deposit
prototype introduced in 0199 and validated in shadow mode in 0200.

The default CPU/OpenMP path remains unchanged. The CUDA path is enabled only at
runtime with:

```bash
MPCD_CUDA_CELL_MOMENTS_USE=1
```

When this flag is set, the collision step replaces the CPU thread-local real
particle deposit by the CUDA atomic deposit:

```text
particles -> cellId, cellCount, cellMass, cellPx, cellPy
```

The rest of the collision step remains CPU-side and unchanged:

```text
virtual-particle wall augmentation
immersed solid wall contribution
cell mean velocity finalization
SRC rotation
```

This deliberately limits the risk: CUDA changes the real-particle moments only,
and the validation script compares the full simulation summaries against the CPU
baseline.

## Runtime switches

```bash
MPCD_CUDA_CELL_MOMENTS_USE=1           # active CUDA deposit
MPCD_CUDA_CELL_MOMENTS_THREADS_PER_BLOCK=256
```

The 0200 shadow mode is still available when the active mode is off:

```bash
MPCD_CUDA_CELL_MOMENTS_SHADOW=1
```

When active mode is enabled, shadow mode is not run, because the CPU deposit is
not computed.

## Build

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
  bash scripts/build_src_mpcd_cuda_0201.sh
```

## Validation

Short validation:

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
GRID_CASES='64:200 128:100' \
PROJECTION_BACKEND=cpu \
bash scripts/run_cuda_cell_moments_active_0201.sh
```

The script runs a CPU-deposit baseline and an active CUDA-deposit run, then uses
`compare_validation_mono_config_0162.py` to check that the physical summaries are
unchanged.

Main output:

```text
dev_history/artifacts/gpu_cuda_deposit_0201/cuda_cell_moments_active_0201.csv
```

Per-run active timing is written by the executable to:

```text
runs/cuda_cell_moments_active_0201_<grid>/tg_periodic_full/cuda_cell_moments_active_0201.csv
```

## Expected interpretation

0200 showed that the standalone/shadow CUDA kernel is numerically accurate but
that the current prototype remains dominated by host-device transfers and per-step
allocation/upload/download overhead. 0201 tests whether replacing the CPU deposit
by this CUDA deposit is already beneficial in the full step.

A negative or neutral performance result is still useful: it means the next
optimization should be a persistent CUDA deposit context, or that the project
should postpone active deposit acceleration until particles remain resident on
the device for later GPU collision/thermostat stages.
