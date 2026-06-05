# 0231 — CUDA resampling shadow plan-policy fix

Patch 0231 fixes the interpretation of the CUDA resampling shadow validation on
real deposits.

The 0227/0228 standalone CUDA diagnostic constructs a simple deterministic
poor/rich compaction and global transfer plan.  In the production resampling
path, however, the CPU transfer plan is local/geometric and order-dependent.
On real simulation deposits, the exact planned mass is therefore not a strict
invariant of the guard classification stage.

The shadow validation now checks the invariants that must match before any
particle mutation is attempted:

- poor receiver cell set;
- rich donor cell set;
- aggregate receiver deficit;
- aggregate donor excess.

The CPU/CUDA planned-transfer mass difference is still written to the shadow CSV
for diagnosis, but it is not fatal by default.

To restore the stricter synthetic-test behavior:

```bash
MPCD_CUDA_RESAMPLING_SHADOW_COMPARE_PLAN=1
```

The main validation script is:

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
GRID_CASES='64:200 128:100' \
PROJECTION_ENABLE=false \
bash scripts/run_cuda_resampling_shadow_0231.sh
```

Expected result: `cuda_resampling_shadow` rows should pass with non-zero
`shadowRows`, zero poor/rich mismatches, zero deficit/excess differences, while
`shadowPlannedAbsDiffMax` may remain non-zero.
