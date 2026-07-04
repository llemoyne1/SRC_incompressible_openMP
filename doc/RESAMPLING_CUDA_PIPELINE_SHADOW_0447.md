# 0447 — Nonzero-plan in-solver CUDA resampling shadow stress

## Purpose

0447 stress-tests the 0446 in-solver CUDA resampling shadow hook on periodic, wall-free, no-chi, no-Darcy, no-inlet/outlet synthetic nonzero-plan cases.

The production CPU path remains authoritative. CUDA replays the resampling pipeline in shadow and the final CPU/GPU states are compared.

## Scope

Validated path:

1. CPU production weighted-resampling pipeline runs normally.
2. CUDA shadow captures the pre-CPU state.
3. CUDA shadow applies extraction/insertion for nonzero passive operations.
4. CUDA shadow applies remap and thermal renormalization.
5. Final CPU/GPU states are compared.

## Acceptance criteria

For every generated CSV:

- `handled == passed`
- `failed == 0`
- `skipped == 0`
- `nonzeroPassiveRows > 0`
- `maxPassiveOps > 0`
- `roleMismatch == 0`
- `typeMismatch == 0`
- `badPrefixCpu == 0`
- `badPrefixGpu == 0`
- mass and fluid payload differences are at roundoff.

## Command

```bash
BIN=build/src_mpcd_base_cuda_q6_resident_periodic_equiv_0446 \
BASE_STRESS_ROOT=runs/0447_nonzero_plan_shadow_stress \
STEPS_LIST="20 100" \
SEEDS="1628638 1628639 1628640" \
RUN_MODES="src-resampling src-q6-resampling" \
SUMMARY_EVERY=1 \
LIVE_VIS_ENABLE=0 \
FILTERED_RECORDING_ENABLE=0 \
bash scripts/run_0447_nonzero_plan_shadow_stress.sh
```

## Expected outputs

- `runs/0447_nonzero_plan_shadow_stress/shadow_stress_summary_0447.csv`
- `runs/0447_nonzero_plan_shadow_stress/shadow_stress_report_0447.md`
