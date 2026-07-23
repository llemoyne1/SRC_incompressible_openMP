# 0490n-fix1 — resident species telemetry after GPU pool mutations

## Problem

In strict 0490n mode the shared CUDA particle state is authoritative.  Population
mutations such as a 0490j merge update the GPU pool and only mirror the compact
active-prefix scalar to the host.  The historical `SpeciesDiagnosticsWriter0490a`
was nevertheless called on the stale host `ParticleState`.  The first merge could
therefore leave the removed slot visible in `species_runtime_0490n.csv`, creating
an apparent species-mass drift although the resident cell deposit remained
conservative.

The 1000-step seed `1628501` exposed the issue at step 269:

- resident pool: 95 Fluid slots, total mass 96;
- stale host writer: 96 Fluid entries, apparent total mass 96.993672088744916.

## Correction

On summary steps the main loop already obtains an up-to-date compact Fluid
snapshot for `summary_runtime.csv` and the cell diagnostics.  In strict 0490n
mode the global species writer now consumes that same snapshot instead of:

1. requesting a full resident-state synchronization; and
2. scanning the stale host storage arrays.

No new GPU-to-host transfer is introduced.  Outside strict resident maintenance
the historical full-state diagnostic path remains unchanged, including latent
particle reporting.

## Validation guard

The 0490n validation script now checks at every step that:

- the sum of `nFluid` in `species_runtime_0490n.csv` equals the resident
  `fluidSlots` count;
- the sum of `nLatent` equals `latentSlots`;
- the summed species mass equals the resident maintenance total mass;
- each individual species mass remains conserved.

This detects stale diagnostic slots immediately after the first split or merge.
