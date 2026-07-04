# 0451 — CUDA resampling upstream apply gate

## Scope

Patch 0451 adds an experimental in-solver CUDA upstream apply gate controlled by:

```bash
MPCD_CUDA_RESAMPLING_UPSTREAM_APPLY_0451=1
MPCD_CUDA_RESAMPLING_UPSTREAM_APPLY_EVERY_0451=1
```

It is intended to be used together with the 0450 strict comparison gate:

```bash
MPCD_CUDA_RESAMPLING_UPSTREAM_SHADOW_0450=1
MPCD_CUDA_RESAMPLING_UPSTREAM_SHADOW_EVERY_0450=1
```

The validated scope remains deliberately narrow:

- periodic boundaries;
- no walls;
- no immersed solid / chi / Darcy;
- no inlet/outlet;
- nonzero resampling transfer plans.

## What changes

0450 proved that CUDA reproduces the CPU upstream:

- deposit / cell id;
- poor-rich classification;
- receiver/donor compaction;
- greedy nearest-donor transfer planner.

0451 adds the next integration layer: the solver accepts the CUDA upstream only through a strict CPU/GPU equivalence gate, then allows the 0448 CUDA backend to mutate the clean particle edits/remap/thermal stages.

## Important limitation

0451A is **not yet the final host-free upstream materializer**.

The current legacy donor-particle selector and passive operation materializer still consume host workspace vectors. Therefore, after CUDA upstream has passed the strict equivalence gate, the host workspace remains as a mirror representation used to feed the existing deterministic operation materialization.

This keeps 0451 conservative:

- CUDA upstream is recomputed and accepted only if identical to CPU at roundoff;
- CPU remains available as the mirror/reference;
- 0448 remains the mutating CUDA backend for extraction/insertion + remap + thermal.

The next step after 0451 is to migrate donor-particle selection and passive operation materialization to CUDA/host-independent buffers.

## Diagnostics

0451 writes:

```text
cuda_resampling_upstream_apply_0451.csv
```

Key pass criteria:

- handled = applied = pass;
- skipped = 0;
- cpuTransferPairs = gpuTransferPairs > 0;
- cpuPassiveOps > 0;
- cellIdMismatch = 0;
- receiverListMismatch = 0;
- donorListMismatch = 0;
- planMismatch = 0;
- maxMassAbs, maxPxAbs, maxPyAbs at roundoff;
- maxPlanMassAbs and maxPlanDistanceAbs at roundoff;
- CPU-baseline vs CUDA-apply final summary delta below tolerance.

## Runner

```bash
BIN=build/src_mpcd_base_cuda_q6_resident_periodic_equiv_0451 \
BASE_UPSTREAM_APPLY_ROOT=runs/0451_upstream_apply_backend_smoke \
STEPS=20 \
SUMMARY_EVERY=1 \
RUN_MODES="src-resampling src-q6-resampling" \
LIVE_VIS_ENABLE=0 \
FILTERED_RECORDING_ENABLE=0 \
bash scripts/run_0451_upstream_apply_backend_smoke.sh
```

The report is:

```text
runs/0451_upstream_apply_backend_smoke/upstream_apply_report_0451.md
```
