# 0113 — Resampling inactive pool/free-list

This patch adds the passive particle-pool layer required before implementing
weighted resampling extraction/insertion.

## Scope

The patch does **not** move particles, change masses, activate latent slots, or
insert/extract fluid.  It only rebuilds deterministic role-index lists from the
current `ParticleState`:

- `fluidSlots`: indices with `role=Fluid`;
- `latentSlots`: indices with `role=Latent`;
- `freeInactiveSlots`: indices with `role=Inactive`, used as the future free-list.

The free-list is rebuilt from particle roles every step and at the initial
summary.  It is therefore passive and reproducible.  Future insertion code will
consume slots from `freeInactiveSlots`; this patch only exposes the infrastructure
and diagnostics.

## Separation from physical type/species

The pool uses only `role`, not `type`.  `type` remains reserved for physical
species/material labels.  Thus a future two-species fluid may have, for example,
`role=Fluid,type=0` and `role=Fluid,type=1`, while inactive slots can retain any
`type` without contributing to fluid dynamics.

## Runtime summary columns

The following columns are added to `summary_runtime.csv`:

- `resampPoolBuilt`
- `resampPoolStorageSlots`
- `resampPoolFreeSlots`
- `resampPoolLatentSlots`
- `resampPoolFluidSlots`
- `resampPoolFirstFreeIndex`
- `resampPoolLastFreeIndex`
- `resampPoolFreeSlotFraction`
- `resampPoolDormantSlotFraction`

`resampPoolFirstFreeIndex` and `resampPoolLastFreeIndex` are `-1` when no inactive
slot is available.

## Validation

Run:

```bash
./scripts/build_src_mpcd_base.sh
./scripts/run_resampling_pool_smoke_0113.sh
```

The smoke test creates a V2 `.smpcd` state with fluid, latent, and inactive slots.
It checks that:

- only fluid particles contribute to mass and real-fluid deposit diagnostics;
- inactive slots appear in the free-list;
- latent slots are counted separately and are not free;
- roles persist after a short classic SRC run;
- no activation/deactivation happens in this passive patch.

## Next step

Patch 0114 can introduce wet/dry cell classification using the real-fluid deposit
from 0112 and the pool/free-list introduced here, still without remapping mass or
momentum.
