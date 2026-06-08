# GPU resampling CUDA — 0299 boundary-aware local population guard

## Scope

Patch 0299 keeps the validated post-SRC sequencing from 0295--0298 and adds a
boundary-aware candidate filter to the local CUDA population guard.  It does not
introduce Q6 CUDA, long-distance transfer, global redistribution, or a hidden
thermostat.

The physical interpretation is unchanged:

```text
SRC classic CUDA produces the fluid state
-> optional conservative mass reconditioning 0296
-> optional local support mutation 0297
-> optional relative-energy restoration 0298
-> 0299 boundary-aware filtering decides where 0297 is allowed to mutate
```

## New filtering rule

The 0297 guard still detects poor/rich cells from the post-SRC cell counts.  With
0299 enabled, candidate cells can be excluded before split/merge if they lie in a
configurable halo adjacent to:

- an open inlet/outlet face;
- a non-periodic wall face;
- an immersed solid surface.

The default is deliberately conservative for the current inlet/outlet CUDA
workflows:

```text
MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0299_BOUNDARY_AWARE=1
MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0299_OPEN_BOUNDARY_HALO_CELLS=1
MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0299_BOUNDARY_HALO_CELLS=0
MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0299_SOLID_HALO_CELLS=0
```

Thus, by default, the local mutating guard does not split/merge directly in the
hard inlet/outlet reservoir layer, while wall and immersed-solid adjacent cells
remain available unless explicitly excluded.

This is a safety policy, not a physical boundary condition.  It prevents the
support controller from fighting the particle reservoir logic.  Later patches may
replace this conservative exclusion by more specialized reservoir-aware split and
merge operations.

## Diagnostics

The existing `cuda_resampling_population_guard_0297.csv` gains the following
columns:

```text
boundaryAware0299
boundaryHaloCells0299
openBoundaryHaloCells0299
solidHaloCells0299
excludedBoundaryCells0299
excludedOpenBoundaryCells0299
excludedSolidHaloCells0299
```

Only candidate poor/rich cells are counted as excluded.  A zero value therefore
means either no cell was excluded or no candidate cell fell in the corresponding
halo during that step.

## Validation protocol

The strict default validation remains non-triggering:

```text
NMIN=0, NMAX=0
```

This confirms that the call path and diagnostics are non-perturbing on the four
strict cases:

1. periodic Taylor--Green;
2. Poiseuille wall;
3. backward step / rectangle;
4. segmented same-face U-box.

Active mutation tests should be interpreted through the guard CSV budgets rather
than strict OFF/ON equality, because split/merge intentionally changes the
particle representation.

## Commands

Build:

```bash
OUT=build/src_mpcd_base_cuda_0299 \
CUDA_ARCH_FLAGS="--generate-code=arch=compute_89,code=sm_89 --generate-code=arch=compute_89,code=compute_89" \
bash scripts/build_src_mpcd_cuda_0299.sh
```

Strict four-case validation:

```bash
BIN=build/src_mpcd_base_cuda_0299 \
FORCE_REBUILD=0 \
NX=64 NY=64 STEPS=80 \
GUARD_EVERY=10 \
bash scripts/run_cuda_resampling_boundary_aware_0299.sh
```

Active boundary-aware U-box probe:

```bash
BIN=build/src_mpcd_base_cuda_0299 \
FORCE_REBUILD=0 \
RUN_TG=0 RUN_POISEUILLE=0 RUN_STEP=0 RUN_SEGMENTED=1 RUN_VK=0 \
NX=64 NY=64 STEPS=80 \
GUARD_EVERY=20 \
GUARD_NMIN=12 GUARD_NTARGET=20 GUARD_NMAX=32 \
RESTORE_ENABLE=1 \
OPEN_BOUNDARY_HALO_CELLS=1 \
bash scripts/run_cuda_resampling_boundary_aware_0299.sh
```

For this active probe, inspect `cuda_resampling_population_guard_0297.csv`, in
particular `splitApplied`, `mergeApplied`, the mass/momentum/Krel error columns,
and the 0299 exclusion counters.
