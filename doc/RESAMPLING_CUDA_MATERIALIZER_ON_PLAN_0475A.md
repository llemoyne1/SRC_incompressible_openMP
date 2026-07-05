# 0475a CUDA materializer on-plan trigger

0475 added a shared-state materializer path, but fixed-cadence materializer calls can occur when `workspace.resampling.transferPlan` is empty. In that case the 0453 diagnostic returns before entering the 0475 shared-state branch, producing `mat_pass > 0` but `mat_shared = 0` and `mat_apply = 0`.

0475a adds `MPCD_CUDA_RESAMPLING_MATERIALIZER_ON_PLAN_0475A=1`, which triggers 0453 opportunistically when the real transfer plan and passive extraction operation list are present.

This is still a gated path: CPU operations remain available for comparison, and the CUDA materializer is applied only on PASS.
