# 0439 — CUDA resampling deposit/classification shadow validator

## Scope

This patch starts the CUDA-resident resampling work without changing solver physics.
It adds a standalone validator for the first resident building block:

- deposit active-fluid particles from an already-uploaded `CudaParticleState`;
- reuse persistent `CudaCellWorkspace` cell arrays;
- download only deposit arrays for comparison;
- compare against the existing CPU `deposit_weighted_real_fluid()` reference.

It does **not** enable a new production backend and does **not** add a public solver parameter.

## Why standalone first

The clean periodic 0438H profile established that `src-resampling` and
`src-q6-resampling` are identical to their non-resampling references at roundoff
when CUDA-local resampling and guards are neutralized. Therefore the next safe
step is not to change the production path, but to validate a resident deposit
shadow against the CPU deposit reference.

## Validator

Files:

- `src/main_validate_cuda_resampling_deposit_shadow_0439.cpp`
- `scripts/build_validate_cuda_resampling_deposit_shadow_0439.sh`
- `scripts/run_validate_cuda_resampling_deposit_shadow_0439.sh`

Synthetic periodic cases:

1. shear, uniform mass, no grid shift;
2. shear, uniform mass, shifted grid;
3. Taylor--Green, variable mass, no grid shift;
4. Taylor--Green, variable mass, shifted grid.

The validator compares:

- cell id for every active particle;
- per-cell count, mass, Px, Py, Ux, Uy;
- aggregate total mass and momentum;
- poor/rich classification counts derived from the CUDA deposit arrays.

## Expected result

The run should print `CUDA_RESAMPLING_DEPOSIT_SHADOW_0439 PASS` and produce a CSV
with all `pass=1`, `cellIdMismatch=0`, `maxCountDiff=0`.
Floating differences in mass and momentum are expected to be at atomic-add roundoff.
