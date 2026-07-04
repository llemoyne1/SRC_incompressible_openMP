# 0468 — Deferred resident-state download probe

0468 is a limited architectural probe built on 0467B.

0467B proved that the CUDA resampling resident core can be called from a caller-owned `CudaParticleState`. 0468 goes one step further: the caller invokes the resident core with `downloadState=false`, then explicitly downloads the final particle state only after the gate/apply status is known.

This is still transaction-safe and not yet a multi-step resident run:

- the caller still creates a CPU rollback object `tmp`;
- the caller still uploads `tmp` into a CUDA state;
- the resident core mutates that CUDA state;
- the resident core does **not** perform the final state download;
- after a successful gate/apply, the caller downloads the state into `tmp` and commits it.

The point is architectural: the final state download is no longer hard-wired inside the resident core. This prepares a later patch where the caller can keep a `CudaParticleState` alive across several calls or steps and postpone the full host download.

Environment flag:

```bash
MPCD_CUDA_RESAMPLING_DEFER_RESIDENT_DOWNLOAD_0468=1
```

Expected validation:

- `residentCore0467=1` on all handled carrier rows;
- `residentExternal0467B=1` on all handled carrier rows;
- `residentDeferredDownload0468=1` on all handled carrier rows;
- strict summary equivalence remains at roundoff level.
