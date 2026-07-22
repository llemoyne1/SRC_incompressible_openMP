# 0490d — Phase-aware resampling mass closure

This patch is the first opt-in step where the registered species change the
resampling physics.

When `speciesResamplingMassClosureEnable=true`, each non-empty wet cell receives:

- a local occupancy proxy `w_s = M_s / Mref_s`;
- a local target mass `Mtarget = Mcell / sum_s(w_s)`;
- a local closure strength equal to the occupancy-weighted mean of the declared
  species strengths, multiplied by the existing closed-capacity factor;
- one common mass scale for every particle in the cell.

The common scale preserves local species fractions exactly. A pure liquid with
closure strength 1 is closed to its declared reference mass, a pure gas with
strength 0 is not mass-closed, and a mixed cell receives an intermediate
closure.

The switch is disabled by default. In 0490d the implementation is CPU-authoritative
and is deliberately incompatible with `resamplingMassGuardEnable=true` and
`closedCapacityResponseEnable=true`. Q6 remains species-blind until the next
SURF stages.
