# 0166 — population-guard candidate lists and counters

Base: clean `SRC_openMP_optimized` state after the validated 0161/0162 CPU/OpenMP stage and the 0165 guard profiler.

This patch is intentionally limited to the population-support guard. It does not touch Q6/CG, closed-capacity/virial, `mass_guard`, thermal renormalization, or particle-cell deposits.

## Changes

1. Build compact `overfull` and `underfull` candidate-cell lists from the current per-cell counts before the two mutating population-guard loops.
2. Iterate the overfull extraction loop only over `overfullCandidateCells`.
3. Iterate the underfull split loop only over `underfullCandidateCells`.
4. Preserve increasing cell-index order, therefore preserving the deterministic order of the original full-domain scans.
5. Add counters:
   - `populationGuardOverfullCandidateCells`
   - `populationGuardUnderfullCandidateCells`
   - `populationGuardOverfullEditedCells`
   - `populationGuardUnderfullEditedCells`
6. Add aggregate metadata rows to `resampling_guard_profile_0166.csv` reporting total and mean candidate/edited cells per population-guard call.

## Validation target

The expected improvements should appear primarily in:

- `population_guard,overfull_extraction_loop`
- `population_guard,underfull_split_loop`
- global `resampling_population_guard`

The functional counters should remain coherent with the previous run:

- `q6Iterations`
- `resampMRelRms`
- `resampTransferPairs`
- `resampSelectedDonorParticles`
- split/extraction population-guard counters

## Build

```bash
BUILD_PROFILE=native ./scripts/build_src_mpcd_base_optimized_0156.sh
```

## Run

```bash
RUN_ROOT=runs/performance_profile_0166_resamp_guard \
THREAD_LIST="1 2 4 8" \
CASE_LIST="q6_resampling" \
STEPS=500 \
./scripts/run_performance_profile_0166.sh
```

Outputs:

- `perf_summary_0166.csv`
- `phase_profile_0166.csv`
- `phase_profile_top_0166.csv`
- `q6_cg_profile_0166.csv`
- `q6_cg_profile_top_0166.csv`
- `resampling_guard_profile_0166.csv`
- `resampling_guard_profile_top_0166.csv`

## Notes

The candidate lists are workspace scratch buffers stored in `WeightedRealFluidDepositWorkspace`, so capacity is reused across steps and no repeated allocation should occur after the initial sizing.
