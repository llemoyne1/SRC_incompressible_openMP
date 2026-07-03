# Resampling inactive-pool O(1) targeted removal (0436)

Date: 2026-07-02

## Problem

The initially empty `1200 x 300`, `gamma=10` injection case reserves about
3.6 million inactive slots. Each CPU resampling insertion previously performed
`std::find` followed by `std::vector::erase` in that pool. On a controlled
50-step run, `resampling_insertion` consumed 121.87 s (90.39% of profiled time)
and total elapsed time was 139.88 s, versus 7.52 s for SRC alone.

## Implementation

`ResamplingParticlePoolWorkspace` now maintains the existing ordered free-slot
stack, an inverse `slot -> stack position` index, an explicit live free-slot
count, and the first potentially live stack position.

Targeted removal marks the selected entry as a tombstone in O(1). Stack pop
removes stale suffix entries lazily before selecting the last live entry. Push
appends a new live occurrence. This preserves the old stack order exactly,
including remove/pop/push sequences, unlike swap-with-last removal.

CPU insertion, CUDA insertion preparation and persistent-active CUDA insertion
preparation all use the common removal primitive. Pool diagnostics and guards
use the explicit live count because vector storage can contain tombstones until
the next pool rebuild.

## Validation status

- Full CUDA production build: PASS.
- `git diff --check`: PASS.
- Ordered-pool model test: PASS for 20 deterministic seeds x 2,000 mixed
  targeted-remove/pop/push operations against the former ordered-vector model.
- A preliminary swap-with-last implementation reduced the identical 50-step
  run from 139.88 s to 16.75 s, but changed the final trajectory and was rejected.
- Final order-preserving CUDA rerun 1: 19.61 s elapsed; insertion phase 0.0431 s.
- Final order-preserving CUDA rerun 2: 19.37 s elapsed; insertion phase 0.0453 s.
- Pre-optimization reference: 139.88 s elapsed; insertion phase 121.87 s.
- Elapsed speedup: 7.17x using the mean final elapsed time.
- Insertion-phase speedup: about 2,757x using the mean final insertion time.
- Against SRC alone (7.52 s), the optimized complete resampling path remains
  about 2.59x slower on this short near-empty case.

The CUDA path is not bitwise deterministic: the two final runs differ by 0.30%
in final fluid population, 0.054% in total mass and 3.1% in estimated `kBT`.
The pre/post-optimization differences in the principal physical quantities are
within the same run-to-run variability envelope. Both final runs report zero
missing free slots, zero non-inactive insertion sources, exactly zero insertion
mass residual, and remap/thermal momentum residuals below `2.3e-15`.

The optimization is therefore validated for pool invariants, conservation and
performance. It is not evidence of trajectory-wise reproducibility; a separate
determinism project would be required to remove atomic/stochastic run ordering.
