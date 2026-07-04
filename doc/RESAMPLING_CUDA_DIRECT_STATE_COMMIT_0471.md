# 0471 — Direct-state commit for CUDA resampling resident carrier

This patch adds a controlled acceleration path for the CUDA resampling resident carrier.

Previous validated path:

```text
ParticleState tmp = state
upload tmp -> CudaParticleState
resident carrier core mutates device state
download mutated device state -> tmp
state = std::move(tmp)
```

0471 path, enabled by `MPCD_CUDA_RESAMPLING_DIRECT_STATE_COMMIT_0471=1`:

```text
host ParticleState remains unchanged
upload state -> caller-owned CudaParticleState
resident carrier core mutates device state with downloadState=false
if gate/apply succeeds: download mutated device state directly -> state
if gate/apply fails: no download, original host state is preserved
```

This removes the CPU rollback copy `ParticleState tmp = state` from the CUDA device-carrier path while retaining transaction safety at the host-state level.

## Flags

Required validation flags normally used with this path:

```bash
MPCD_CUDA_RESAMPLING_PIPELINE_APPLY_0448=1
MPCD_CUDA_RESAMPLING_DEVICE_CARRIER_0455=1
MPCD_CUDA_RESAMPLING_THRUST_CELL_LIST_MATERIALIZER_0460=1
MPCD_CUDA_RESAMPLING_SPARSE_DEVICE_CARRIER_GATE_0461=1
MPCD_CUDA_RESAMPLING_RESIDENT_EXTERNAL_CARRIER_0467B=1
MPCD_CUDA_RESAMPLING_DEFER_RESIDENT_DOWNLOAD_0468=1
MPCD_CUDA_RESAMPLING_DIRECT_STATE_COMMIT_0471=1
```

## Expected result

The probe should show:

- strict CPU/CUDA equivalence, with max summary deltas near prior 0468 values;
- `residentCore0467=1`, `residentExternal0467B=1`, `residentDeferredDownload0468=1`, `residentDirectCommit0471=1` on handled device-carrier CSV rows;
- `tmpCopySeconds=0` in `cuda_resampling_transaction_0466.csv` for the direct path;
- performance improvement limited to the removed CPU copy. Upload/download still occur once per handled step.

This patch is not yet a fully resident multi-step path. It is the first acceleration-oriented step after the 0467–0470 architecture refactor.
