# Resampling CUDA clean branch start 0001

Date: 2026-06-18

## Origin

- Source worktree: `E:\SRC_MPCD_dev\SRC_GPU-TOPO`
- Source branch: `topo/darcy-brinkman-viz`
- Source commit: `98edb0f 0358-topo: validate Darcy-Brinkman path and wake diagnostics`
- New worktree: `E:\SRC_MPCD_dev\SRC_GPU-RESAMP`
- New branch: `resamp/cuda-topo-clean`

## Sparse checkout scope

Initial materialized scope:

- `src/`
- `include/`
- `init/`
- `scripts/`
- `matlab/`
- `data/`
- `doc/`
- `docs/`
- `README.md`
- `.gitignore`

This keeps the full Git history available while avoiding direct work inside the
large `SRC_GPU-TOPO` tree. The source worktree is left untouched.

## Working rules

- No file or directory deletion without explicit validation.
- Prefer additive changes: new source files, new runners, new analysis scripts,
  and new documentation.
- Existing validated paths must remain available for comparison.
- Resampling CUDA validation must be separated from topology changes first.

## First milestone

RCUDA-CLEAN-1:

Revalidate the existing CUDA resampling path on short baseline cases before
introducing chi-aware behavior:

- Taylor-Green / periodic
- Poiseuille or wall-simple channel
- backward step or inlet/outlet support case

Required observables:

- cell population support, including empty wet cells;
- min/mean/max particle mass;
- split/merge activity;
- global mass, momentum, and relative-energy conservation;
- cell temperature;
- velocity outliers;
- runtime and inactive-pool cost indicators.
