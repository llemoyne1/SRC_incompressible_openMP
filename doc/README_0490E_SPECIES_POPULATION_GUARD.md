# 0490e — Species-aware population support guard

This patch makes the CPU weighted-resampling population guard species-aware
behind the explicit opt-in switch:

```text
speciesResamplingPopulationGuardEnable = true
```

The global support policy is unchanged: cells are still classified from the
total particle count using `Nmin/Ntarget/Nmax`. The new logic changes only the
species selected for a local split or same-type merge.

For each non-empty wet cell, the code builds an occupancy proxy

```text
w_s = M_s / referenceCellMass_s
```

and apportions exactly `Ntarget` representative slots between the species. One
slot is reserved for each present species whenever `Ntarget` is large enough;
the remaining slots are assigned by deterministic largest remainder.

- In an under-populated cell, the species with the largest positive population
  deficit is split.
- In an over-populated cell, the species with the largest population surplus
  and at least two representatives is merged.
- Split inherits the parent type and merge remains strictly same-type, so every
  species mass and momentum are conserved by the discrete edit.

The switch is disabled by default and mono-species/legacy trajectories are
unchanged. This milestone is CPU-authoritative. The CUDA population guard still
uses its 0490c species-conservative selection and will receive the same target
composition policy in a later patch.
