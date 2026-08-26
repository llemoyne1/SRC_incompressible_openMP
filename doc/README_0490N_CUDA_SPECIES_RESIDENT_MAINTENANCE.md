# 0490n — integrated CUDA species resident maintenance

Base checkpoint: `3d7ce88` (`0490m: add fast resident CUDA species resampling path`).

## Scope

0490n combines the two remaining particle-scan migrations that were previously
planned as 0490n and 0490o:

1. resident species-aware deposits replacing the legacy weighted real-fluid
   particle scan at initial, post-guard, post-edit and post-remap stages;
2. a deterministic resident GPU role pool/free-list replacing the CPU pool
   rebuild at initial, post-guard and post-edit stages.

The two components remain separately switchable:

```text
speciesResamplingCudaResidentDepositsEnable = true
speciesResamplingCudaResidentPoolEnable = true
```

The integrated production gate is:

```text
speciesResamplingCudaResidentMaintenanceStrict = true
speciesCudaResidentMaintenanceDiagnosticsFilename = cuda_species_resident_maintenance_0490n.csv
```

Strict mode requires both components and aborts before any CPU weighted deposit
or CPU pool rebuild can be used.

## Resident deposit

The authoritative particle state is the shared CUDA state. 0490h computes
`N[c,s]`, `M[c,s]`, `Px[c,s]` and `Py[c,s]` directly on the GPU. 0490n derives
the legacy aggregate cell fields from those species fields. Only compact cell
arrays are downloaded for the still-host-side cell policy and diagnostics:

- total count, mass and momentum per cell;
- mean cell velocity;
- wet/poor/rich masks and compact receiver/donor lists.

No active-particle position, mass or velocity scan is executed on the CPU.
The native 0490k planner reuses the species workspace refreshed by 0490n and
therefore skips its redundant species deposit.

## Resident pool/free-list

The role array is consumed directly from the shared CUDA particle state. CUB
stable device selection creates deterministic ascending-index lists for:

- `Fluid` slots;
- `Latent` slots;
- `Inactive` free slots.

The list storage and counters are persistent in
`CudaSpeciesResidentMaintenanceWorkspace0490n`. The host receives only role counts and the first/last active/free indices for
diagnostics. The active-prefix invariant is checked explicitly and only the
`NactiveFluid` scalar is mirrored back to the host; no particle array is
downloaded. In strict mode the empty legacy host vectors cannot be consumed by
a CPU mutation path.

## Additional synchronization removed

With resident post-remap deposits active, 0490i no longer downloads the complete
active mass/velocity prefix after every closure step. The next resident deposit
reads the corrected shared CUDA state directly. Normal summary, dump and
visualization synchronization remains explicit and unchanged.

## Current validated subset

The correctness-first gate remains aligned with 0490m:

- fully periodic boundaries;
- full static fluid domain;
- no immersed solid;
- registered species types;
- resident CUDA population guard when the guard is enabled;
- resident CUDA mass closure when closure is enabled;
- latent activation disabled;
- thermal renormalization disabled.

This restriction avoids silently approximating active-domain masks or thermal
reference cell maps. Later patches may widen the geometry subset after dedicated
equivalence tests.

## Validation

Run:

```bash
LIVE_PROGRESS=1 \
BIN=build/src_mpcd_base_cuda_q6_resident_0490n \
bash scripts/run_0490n_cuda_species_resident_maintenance_validation.sh
```

The script performs:

1. the complete 0490m non-regression suite;
2. a direct species-filtered transfer smoke with strict 0490n maintenance;
3. three integrated 100-step multi-species runs;
4. exact per-species mass checks;
5. resident pool integrity checks;
6. an audit requiring zero time in every replaced CPU maintenance phase;
7. verification that 0490i active-prefix downloads remain zero.

Expected final audit:

```text
[0490n] cpu_weighted_deposit_calls=0
[0490n] cpu_pool_rebuild_calls=0
[0490n] cpu_post_edit_deposit_calls=0
[0490n] cpu_post_remap_deposit_calls=0
[0490n] remaining_cpu_scope=compact_cell_policy_mirror
[0490n] PASS
```

The remaining host work is proportional to the number of cells, not the number
of particle slots. It keeps the legacy policy/summary interface coherent while
the physical deposit, role classification and free-list construction remain GPU
resident.
