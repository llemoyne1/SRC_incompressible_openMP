# 0490f — mixed-species CUDA empty-cell refill

## Scope

Patch 0490f extends the 0319/0490c CUDA empty-cell refill so that a temporarily
empty cell previously containing several registered species can be reconstructed
without collapsing to one type.

The feature is opt-in:

```text
cudaResamplingEmptyRefillSpeciesCompositionEnable = true
```

It requires:

```text
cudaResamplingEmptyRefillEnable = true
speciesRegistryEnable = true
speciesRequireRegisteredTypes = true
```

Legacy runs are unchanged when the new switch is false.

## Memory carried on the resident CUDA path

For every cell and every registered species, the guard stores the last valid
species mass

```text
M_last[c,s]
```

alongside the pre-existing total mass and barycentric velocity memory. A mixed
cell is eligible for refill only if the refill target contains at least one
representative slot for every remembered species.

## Reconstruction rule

The refill target population is shared among remembered species with a
deterministic largest-remainder allocation. Every represented species receives
at least one particle. The pre-correction mass assigned to species `s` is exactly
`M_last[c,s]`, independently of the number of representatives allocated to it.

Therefore the local remembered mass fractions are restored before the global
conservation correction.

## Species-conservative correction

The old single global refill scale is insufficient for a mixed cell because it
can change the total mass of each species separately. Patch 0490f measures, for
every registered species,

```text
mass, Px, Py before refill
mass, Px, Py added by refill
```

and applies one mass scale and one velocity shift per species. This restores the
pre-refill global mass and momentum of every species to floating-point tolerance.
The correction remains global within each species; it does not introduce a
separate pressure field or species-specific Q6 solve.

## Deliberate limits

- Only registered particle types participate.
- A refill is rejected if the target population is smaller than the number of
  remembered species.
- A strict error is raised if refill would recreate a species that is absent
  from the current active population, because exact global species conservation
  would then be impossible without an external reservoir.
- Q6 remains unchanged.
- The CUDA split/merge selection is not yet composition-directed; 0490e covers
  that policy on the CPU guard.

## Smoke test

```bash
LIVE_PROGRESS=1 \
BIN=build/src_mpcd_base_cuda_q6_resident_0490f \
bash scripts/run_0490f_mixed_species_refill_smoke.sh
```

The test starts with a mixed liquid/gas cell, lets it become empty through
periodic streaming, and checks that:

- both species are recreated in the cell;
- the remembered gas/liquid mass ratio is restored;
- total liquid mass is conserved;
- total gas mass is conserved;
- total momentum is conserved separately for each species;
- the old 0490c mixed-cell rejection counter remains zero.
