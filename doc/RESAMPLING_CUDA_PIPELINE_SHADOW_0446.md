# 0446 — In-solver CUDA clean pipeline shadow with non-zero transfer plans

Scope: extend the experimental in-solver shadow hook introduced in 0445 so it
also replays passive extraction/insertion operations when the CPU weighted
resampling path builds a non-empty transfer plan.

The CPU path remains authoritative.  The hook:

1. captures the particle state and passive operation list before CPU
   extraction/insertion;
2. lets the normal CPU path apply extraction, insertion, remap and thermal
   renormalization;
3. replays extraction/insertion on a `CudaParticleState` shadow copy using the
   already validated 0239 device operations;
4. replays remap and thermal renormalization using the 0443 kernels;
5. compares the final CPU and CUDA-shadow states.

The existing runtime flag remains the activation mechanism:

```bash
MPCD_CUDA_RESAMPLING_PIPELINE_SHADOW_0445=1
```

No production mutation is performed by CUDA in this patch.

## Smoke runner

`run_0446_periodic_nonzero_plan_shadow_smoke.sh` generates a periodic,
wall-free, no-chi/no-Darcy/no-inlet-outlet state with paired poor/rich cells.
This forces a non-zero passive transfer plan while staying outside the wall or
solid cases that are excluded from physical equivalence validation.

Recommended smoke:

```bash
BIN=build/src_mpcd_base_cuda_q6_resident_periodic_equiv_0445 \
BASE_RUN_ROOT=runs/0446_periodic_nonzero_plan_shadow_smoke \
STEPS=5 SUMMARY_EVERY=1 \
RUN_MODES="src-resampling src-q6-resampling" \
LIVE_VIS_ENABLE=0 FILTERED_RECORDING_ENABLE=0 \
bash scripts/run_0446_periodic_nonzero_plan_shadow_smoke.sh
```

PASS criteria:

- `handled == passed`;
- `skipped == 0`;
- at least one row has `passiveOps > 0`;
- `roleMismatch = 0`;
- `typeMismatch = 0`;
- `badPrefixCpu = badPrefixGpu = 0`;
- mass, momentum and kinetic-energy CPU/GPU deltas are at roundoff level;
- fluid-slot payload differences are at roundoff level.

