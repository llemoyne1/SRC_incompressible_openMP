# 0235 — CUDA resampling transfer shadow coverage expansion

This patch continues the CUDA resampling chantier after the 0234 real-deposit
shadow transfer validation.

## Motivation

Patch 0234 was deliberately conservative: it allowed at most one synthetic
insertion per receiver cell.  That policy validated the conservative
particle-splitting primitive, but it artificially reduced the number of real
resampling transfers checked in shadow mode.

Patch 0235 keeps the same safety rule for donors — one donor particle is used at
most once — but allows several transfers to target the same receiver cell, with a
distinct synthetic insertion particle for every transfer.

The default is therefore closer to a real resampling workload while remaining a
shadow-only validation: the production particle state is not modified by CUDA.

## Runtime flags

Default expanded coverage:

```bash
MPCD_CUDA_RESAMPLING_TRANSFER_SHADOW=1
MPCD_CUDA_RESAMPLING_TRANSFER_SHADOW_UNIQUE_RECEIVER=0
```

Recover the 0234 one-receiver policy:

```bash
MPCD_CUDA_RESAMPLING_TRANSFER_SHADOW_UNIQUE_RECEIVER=1
```

The maximum number of shadow transfers is increased to 8192 in the 0235 harness:

```bash
TRANSFER_MAX_TRANSFERS=8192
```

## Validation

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
GRID_CASES='64:200 128:100' \
PROJECTION_ENABLE=false \
bash scripts/run_cuda_resampling_transfer_shadow_0235.sh
```

Expected criteria:

- baseline and shadow runs pass the 0162 comparison;
- guard rows pass;
- transfer rows pass;
- `transferCellMismatch = 0`;
- `transferRoleMismatch = 0`;
- mass and momentum conservation remain at roundoff.

This patch still does not activate CUDA resampling in the main simulation.  It
only improves coverage of the real-deposit shadow mutation before the active
resampling patch.
