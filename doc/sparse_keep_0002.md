# Sparse keep 0002

Date: 2026-06-18

## Objective

Reduce the `SRC_GPU-RESAMP` worktree to the material needed for the CUDA
resampling cleanup branch, without deleting repository history or tracked files.

This is a sparse-checkout-only cleanup. Files outside the patterns below remain
in Git history and can be restored by widening the sparse checkout.

## Branch context

- Worktree: `/mnt/e/SRC_MPCD_dev/SRC_GPU-RESAMP`
- Branch: `resamp/cuda-topo-clean`
- Source commit: `98edb0f 0358-topo: validate Darcy-Brinkman path and wake diagnostics`

## Kept core scope

Always kept:

- `src/`
- `include/`
- `init/`
- `README.md`
- `.gitignore`
- `livevis_control.kv`

## Kept documentation scope

Kept documentation is limited to the current branch notes and the most relevant
CUDA resampling, CUDA Q6/non-regression, active-prefix, livevis, and topology
references:

- `doc/resamp_cuda_start_0001.md`
- `doc/sparse_keep_0002.md`
- `doc/GPU_RESAMPLING_CUDA_*.md`
- `doc/GPU_NONREGRESSION_Q6_RESAMPLING_VIRIAL_0326*.md`
- `doc/GPU_CUDA_INACTIVE_*.md`
- `doc/GPU_CUDA_COMPACT_*.md`
- `doc/active_prefix_capacity_*.md`
- `doc/README_018*_CUDA_Q6*.md`
- `doc/README_02*_CUDA_RESAMPLING*.md`
- `doc/README_*livevis*.md`
- `doc/README_portable_livevis_demos_0337.md`
- `doc/src_mpcd_cuda_*resampling*.csv`
- `doc/src_mpcd_cuda_*livevis*.csv`
- `doc/topo_*.md`
- `doc/injection_fill_resampling_validation_0342a_livevis.md`

## Kept script scope

Kept scripts are restricted to current CUDA resampling builds/runs/analyzers,
portable resampling demos, selected non-regression scripts, livevis/topology
helpers, and topology post-processing hooks:

- CUDA build scripts from the resampling/topology period
- CUDA resampling runners and analyzers
- visual/portable resampling demo runners
- Q6/resampling/virial non-regression runners
- topology chi/Darcy/NACA/Von Karman runners
- MATLAB topology plot/wake-density wrappers

## Kept MATLAB scope

`matlab/` is kept broadly for this first sparse tightening. It contains
post-processing and state-generation dependencies that are not yet cleanly
separable. A later sparse pass can reduce it after runner dependencies are
verified.

## Working rule

Do not use `git rm` for this cleanup. If a missing file is needed by a build,
runner, or analysis, widen the sparse checkout and document the reason in a new
note.
