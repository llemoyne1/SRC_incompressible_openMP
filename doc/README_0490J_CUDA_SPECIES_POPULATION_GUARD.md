# 0490j — Resident CUDA species-aware population guard

## Scope

Patch 0490j ports the species-selection policy validated by 0490e into the
existing resident CUDA population guard 0297. The global support band remains
`Nmin/Ntarget/Nmax`; the new CUDA logic only determines which registered
species supplies each local split or same-species merge.

For each wet candidate cell, the resident 0490h deposit provides `N_{c,s}` and
`M_{c,s}`. A deterministic target population is reconstructed from
`M_{c,s}/Mref_s`, including one representative per present species whenever
`Ntarget` permits and largest-remainder apportionment of the remaining slots.
The most deficient species is selected for a split and the most excessive
species with at least two representatives is selected for a merge.

The conservative mutation itself remains the validated 0297 implementation:
split inherits `type`; merge requires equal types; mass and momentum are
conserved locally. The CPU 0490e guard is bypassed when the CUDA backend is
enabled, preventing a double edit in the same step.

## New parameter

```text
speciesResamplingPopulationGuardCudaEnable = true
```

This requires the existing CPU policy switch, species registry, strict type
validation, explicit positive `resamplingPopulationNMin/NTarget/NMax`, and a
resident CUDA classic path.

## Non-goals

0490j does not yet port long-distance donor/receiver planning (0490g) and does
not modify Q6. One local split or merge per candidate cell and per invocation
is retained from 0297.
