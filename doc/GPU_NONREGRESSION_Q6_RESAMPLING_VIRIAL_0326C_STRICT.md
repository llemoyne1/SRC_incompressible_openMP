# GPU non-regression Q6/resampling/virial — 0326c strict audit

0326b checks that the selected validation runs exit with code 0.  0326c is a
stricter parser: it verifies that each advertised physical module was actually
exercised in the output summaries.

Expected strict checks:

- `q6_only_tg`: `q6Applied=1`, `q6Converged=1`, `resampComputed=0`.
- `resampling_only_tg`: `q6Applied=0`, `resampComputed=1`.
- `hybrid_cuda_q6_resampling_tg`: CUDA persistent collision rows exist,
  `thermostatAppliedOnGpu=0`, `q6Applied=1`, `q6Converged=1`,
  `resampComputed=1`.
- `hybrid_cuda_piston_virial`: CUDA persistent piston collision rows exist,
  `thermostatAppliedOnGpu=0`, `q6Applied=1`, `q6Converged=1`,
  `resampComputed=1`, `capacityResponseEnabled=1`,
  `capacityResponseComputed=1`, `capacityVirialKickApplied=1`.

This is script-only and does not modify the solver.
