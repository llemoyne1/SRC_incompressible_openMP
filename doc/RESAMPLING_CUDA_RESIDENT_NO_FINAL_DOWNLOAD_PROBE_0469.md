# 0469 — Resident no-final-download diagnostic probe

This patch adds a bounded diagnostic shadow path for the CUDA resampling resident core.

The normal 0468 transaction path remains active and unchanged. When
`MPCD_CUDA_RESAMPLING_RESIDENT_NO_FINAL_DOWNLOAD_PROBE_0469=1` is set, the
0448 caller additionally runs a shadow resident-core application on a caller-owned
`CudaParticleState` with `downloadState=false` and intentionally does not download
that mutated particle state back to the host. The mutated shadow CUDA state is then
discarded, and the normal 0468 transaction path performs the actual solver mutation.

This proves a narrower architectural point: the 0467 resident core can materialize,
gate, and apply operations on a caller-owned CUDA particle state without any final
`download_all` being required for the carrier/gate itself. It is not yet a multi-step
resident solver path, because CPU upstream still requires a host-authoritative
`ParticleState` for the next step.

Expected validation:

- regular CPU/CUDA summaries still pass;
- `cuda_resampling_resident_nodownload_0469.csv` exists in each CUDA run directory;
- all no-final-download probe rows have `ok=1`;
- `stateDownloadSeconds=0` in the no-final-download probe rows;
- the regular 0468 path still has `residentCore0467=1`, `residentExternal0467B=1`, and
  `residentDeferredDownload0468=1`.
