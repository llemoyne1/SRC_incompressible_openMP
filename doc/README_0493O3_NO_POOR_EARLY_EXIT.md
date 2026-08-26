# 0493o3 — no-poor early exit for the target-driven Neff split guard

## Scope

0493o3 optimizes only the resolved 0493o1 split-only mode:

- `resamplingEnable=true`;
- insertion enabled;
- extraction disabled;
- remap disabled;
- CUDA active-prefix carrier authoritative;
- no empty refill and no legacy 0490j population guard layered onto the same call.

No simulation parameter or environment flag is added.

## Algorithmic change

The resident species-cell deposit remains the source of `count`, `mass` and
`massSquared`.  A light CUDA detection pass computes

`Neff = (sum m)^2 / sum(m^2)`

for every enabled cell/species pair and downloads only the poor-pair count plus
the diagnostic minimum.  If no non-empty pair has `Neff < NMin`, the guard:

- does not compact particle indices;
- does not select or sort candidate representatives;
- does not build a split plan;
- does not launch the split kernel;
- does not perform the post-mutation cell deposit;
- does not run the pre/post kinetic validation, because no state was changed;
- returns with the resident CUDA state still authoritative.

When at least one pair is poor, the 0493o1 planning and equal-mass split path is
unchanged.  The only additional active-path operation is the scalar poor-count
read required to decide whether the fast exit is legal.

## Diagnostics

The existing `cuda_resampling_population_guard_0297.csv` receives appended
0493o3 columns:

- `noPoorEarlyExit0493o3`;
- resident species-deposit and pre-mutation kinetic timings;
- light reset, classification and scalar-download timings;
- candidate, plan, apply and final-diagnostic timings;
- post-mutation validation timing.

A supplemental buffered file,
`cuda_resampling_population_guard_caller_0493o3.csv`, separates downstream
caller cost into state synchronization, initial CPU/resident maintenance,
authority mapping, post-guard maintenance and the remaining generic pipeline.
This file is diagnostic only and does not control execution.

## Safety boundary

The fast exit is taken only after a resident cell/species classification has
reported zero poor non-empty pairs. Empty cell/species pairs remain counted but
are not filled by 0493o3. The path does not alter particle positions, velocities,
masses, types, roles, active-prefix length or CUDA authority.
