# 0490p — resident CUDA cell policy and strict zero-resampling-CPU audit

## Purpose

0490n removed the CPU particle scans used by deposits and pool maintenance, but
still downloaded the complete species-by-cell deposit and rebuilt the
wet/poor/rich cell policy in a host loop. 0490p removes that final per-cell CPU
scope from the validated resident multi-species path.

## Changes

- Build the wet, poor, rich and target-band masks directly on CUDA from the
  authoritative resident 0490h species deposit.
- Keep those masks resident in `CudaSpeciesResidentMaintenanceWorkspace0490n`.
- Download only one fixed-size aggregate policy summary for runtime diagnostics.
- Hand the resident wet-cell mask directly to the native 0490k planner; no
  per-step cell-policy H2D copy remains.
- Permit the 0490i production fast path to consume the aggregate resident policy
  diagnostics without requiring a host per-cell mass reference.
- Extend the 0490n strict runner so any host policy array, mirror download or
  policy-mask upload is fatal.

## Preserved scope

The validated production subset remains the 0490n subset: fully periodic,
wall-free, no immersed solid, no latent activation and no thermal
renormalization. Automatic target-cell mass remains supported by the serial
correctness-first CUDA policy kernel.

## Required invariants

For every resident deposit refresh:

- `cellPolicyDeviceResident=1`
- `policyHostArrayEntries=0`
- `cellMirrorDownloadBytes=0`
- `hostCellMirrorSeconds=0`
- `policySummaryDownloadBytes>0`

For every native transfer plan:

- `residentPolicyDeviceHandoff=1`
- `policyMaskUploadSkipped=1`

The validation summary must end with:

- `strict_zero_resampling_cpu=1`
- `remaining_cpu_scope=none`
