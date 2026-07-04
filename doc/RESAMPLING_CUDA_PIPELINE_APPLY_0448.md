# 0448 — Experimental CUDA apply backend for clean resampling pipeline

## Scope

Patch 0448 introduces the first production-mutating CUDA backend for the clean
resampling pipeline under the explicit environment flag:

```bash
MPCD_CUDA_RESAMPLING_PIPELINE_APPLY_0448=1
```

The backend is intentionally limited to the clean pipeline already validated in
0438H and 0439–0447:

1. passive extraction/insertion operations,
2. local mass/momentum remap,
3. local thermal renormalization.

The CPU still performs deposit/classification/planning and the post-apply
diagnostic deposits.  Therefore 0448 is not yet the final fully resident
resampling path, but it is the first step where CUDA becomes authoritative for
the state mutation phases of resampling.

## Explicit exclusions

0448 does not cover:

- population guard,
- mass guard,
- CUDA-local auxiliary recondition/refill paths 0296/0297/0319,
- chi/Darcy/solid-aware applicative validation,
- elimination of all host/device synchronizations.

If unsupported guards are enabled, the solver falls back to the existing CPU
path for the corresponding phase.

## Validation philosophy

The CPU path remains available as the reference.  The runner
`scripts/run_0448_periodic_nonzero_plan_apply_smoke.sh` runs the same synthetic
periodic nonzero-plan case twice:

- CPU baseline: `MPCD_CUDA_RESAMPLING_PIPELINE_APPLY_0448=0`, shadow enabled;
- CUDA apply: `MPCD_CUDA_RESAMPLING_PIPELINE_APPLY_0448=1`, shadow enabled.

The final runtime summary and the 0445 shadow diagnostics are compared.  A pass
requires:

- no shadow failures or skips,
- nonzero passive operation rows,
- CUDA apply diagnostics handled with zero invalid operations,
- final CPU-baseline vs CUDA-apply summary deltas within tight tolerance.

## Build

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
MPCD_ENABLE_LIVE_VIS=1 \
OUT=build/src_mpcd_base_cuda_q6_resident_periodic_equiv_0448 \
bash scripts/build_src_mpcd_cuda_q6_resident_0400.sh
```

## Smoke

```bash
BIN=build/src_mpcd_base_cuda_q6_resident_periodic_equiv_0448 \
BASE_APPLY_ROOT=runs/0448_periodic_nonzero_plan_apply_smoke \
STEPS=20 \
SUMMARY_EVERY=1 \
RUN_MODES="src-resampling src-q6-resampling" \
LIVE_VIS_ENABLE=0 \
FILTERED_RECORDING_ENABLE=0 \
bash scripts/run_0448_periodic_nonzero_plan_apply_smoke.sh
```

Expected output:

```text
PASS-like modes: 2/2
```

