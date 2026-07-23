# 0490m fix2 — species-conservative resident CUDA mass closure

## Failure found by the long validation

The 100-step 0490m run preserved total mass but produced:

```text
type 1: 48.00000000000000 -> 48.13333333333334
type 2: 48.00000000000000 -> 47.86666666666667
```

No population-guard or donor/receiver operation occurred at the sampled step.
The drift came from the 0490i common cell scale. A common factor preserves the
composition of each individual cell, but different factors in cells with
different compositions can change the global mass carried by each registered
species.

## Resident correction

In the 0490m production-fast path, 0490i now builds a species-by-cell scale
matrix on the GPU. Eight alternating balances are applied:

1. normalize columns to the pre-closure global mass of every species;
2. normalize rows toward the requested effective cell masses.

A final species-column normalization makes global mass by registered `type` the
hard invariant. The requested cell masses remain exact when the species support
permits both constraints; otherwise the residual is reported without silently
converting mass from one species into another.

Because species-specific mass factors can change the barycentric velocity of a
cell, a common velocity shift is then applied to all particles in that cell.
This restores the pre-closure cell mean velocity while retaining relative
velocities.

The legacy 0490i equivalence path remains unchanged when
`speciesResamplingCudaResidentFastPathEnable=false`.

## New scalar diagnostics

`cuda_species_mass_closure_0490m.csv` adds:

- `speciesConservativeBalance`;
- `balanceIterations`;
- `maxSpeciesMassRelResidual`;
- `maxCellMassRelResidual`;
- `maxVelocityShift`.

Only three scalar residuals are downloaded. No dense species/cell balance array
is mirrored to the host.
