# 0444 — CUDA resampling clean pipeline shadow validator

Purpose: validate the clean periodic resampling pipeline as a single end-to-end shadow test after the individual semantic locks:

- 0439: deposit/classification CUDA shadow;
- 0440: poor/rich compaction CUDA shadow;
- 0441: transfer planner CUDA shadow;
- 0442: particle extraction/insertion apply CUDA shadow;
- 0443: local mass/momentum remap + thermal renormalization CUDA shadow.

This validator remains standalone. It does not change the production solver and does not introduce a public runtime parameter.

Scope:

- periodic wall-free synthetic cases only;
- no chi/Darcy, no immersed solid, no inlet/outlet;
- clean resampling profile: no local CUDA repair guards, no population/mass guard interpretation;
- CPU reference applies `deposit_weighted_real_fluid`, particle extraction/insertion, local remap, and thermal renormalization;
- CUDA shadow applies the previously validated particle apply kernels followed by CUDA remap/thermal kernels;
- final state invariants and fluid payload are compared.

The test intentionally remains a semantic/finality validator rather than a production-resident performance path. Integration into the main solver should come only after this stage passes.

Expected smoke command:

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
OUT=build/validate_cuda_resampling_pipeline_shadow_0444 \
bash scripts/build_validate_cuda_resampling_pipeline_shadow_0444.sh

BIN=build/validate_cuda_resampling_pipeline_shadow_0444 \
RUN_ROOT=runs/0444_cuda_resampling_pipeline_shadow_smoke \
NX=64 NY=32 GAMMA=20 INACTIVE_SLOTS=1024 SEED=1628638 \
bash scripts/run_validate_cuda_resampling_pipeline_shadow_0444.sh
```

Expected result:

```text
CUDA_RESAMPLING_PIPELINE_SHADOW_0444 PASS cases=4/4
```
