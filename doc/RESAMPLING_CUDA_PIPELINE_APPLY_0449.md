# 0449 — CUDA resampling apply backend stress

This step stress-tests the experimental CUDA apply backend introduced by 0448.

Scope:

- periodic synthetic nonzero-plan cases only;
- no walls, no `chi`, no Darcy/Brinkman, no inlet/outlet;
- `src-resampling` and `src-q6-resampling` are both covered;
- CUDA is authoritative for the clean mutation phases:
  - passive extraction/insertion,
  - local mass/momentum remap,
  - local thermal renormalization;
- CPU still provides deposit/classification, plan construction, orchestration and diagnostics.

The runner repeatedly invokes the 0448 CPU-baseline vs CUDA-apply comparison over several seeds and step counts, then aggregates:

- final summary deltas CPU baseline vs CUDA apply;
- shadow pass/fail/skipped rows;
- apply handled/applied/skipped rows;
- nonzero passive operation coverage;
- role/type/prefix mismatch counts;
- maximum state differences.

Expected result:

```text
PASS-like rows = all rows
maxInvalidOps = 0
maxRoleMismatch = 0
maxTypeMismatch = 0
maxBadPrefixCpu/Gpu = 0
maxAbsMass = 0
maxAbsVx/Vy ~ roundoff
maxSummaryDelta <= 1e-9
```

0449 does not remove the remaining CPU dependencies. It validates that the first production-mutating CUDA backend remains equivalent to the CPU baseline over a small stress matrix.
