# 0475a2 materializer on-plan helper hotfix

Fixes the compile ambiguity introduced by 0475a: the public header declared
`mpcd::cuda_resampling_materializer_on_plan_0475a_requested()` while the CUDA
translation unit also defined an unnamed-namespace helper with the same name.

0475a2 keeps the CUDA helper local to `cuda_resampling_pipeline_shadow_0445.cu`
and uses a local env helper in `src_mpcd_base.cpp` for the on-plan trigger.
