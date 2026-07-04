# 0467B — External resident carrier call path

0467A split the CUDA resampling device carrier into a resident core that operates on a supplied `CudaParticleState&`.

0467B moves one step further: when `MPCD_CUDA_RESAMPLING_RESIDENT_EXTERNAL_CARRIER_0467B=1`, the 0448 transaction wrapper owns the temporary `CudaParticleState`, uploads the CPU transaction state into it, and calls the resident core directly.

This remains transaction-safe and does not yet remove host/device roundtrips:

- `ParticleState tmp = state` is still the rollback/commit object.
- The 0448 wrapper still uploads `tmp` into a CUDA particle state.
- The resident core is called with `downloadState=true`, preserving host state after apply.
- The legacy 0455 wrapper remains available when the 0467B flag is disabled.

The objective is architectural rather than performance-oriented: prove that the resident core can be driven from a caller-owned CUDA state outside the legacy 0455 carrier wrapper. This prepares later patches where the same state can persist across multiple calls and eventually suppress per-call upload/download.

Expected validation:

- strict CPU/CUDA equivalence remains within established tolerances;
- every handled carrier row reports `residentCore0467=1`;
- every handled carrier row reports `residentExternal0467B=1` when the 0467B flag is enabled;
- sparse/full gate behavior remains unchanged.
