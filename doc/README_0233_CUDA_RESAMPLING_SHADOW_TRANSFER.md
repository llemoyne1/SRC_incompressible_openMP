# 0233 — CUDA resampling shadow transfer primitive

This patch adds the first mutating CUDA resampling primitive, but only on a copy/standalone validator.

Validated chain:

1. classify poor/rich cells and build a mass-transfer plan;
2. select one eligible donor particle per transfer;
3. allocate one latent insertion slot per transfer;
4. split bounded donor mass into the insertion slot on CUDA;
5. compare CPU and CUDA particle arrays and invariants.

The primitive preserves global mass and momentum up to floating-point roundoff by copying the donor velocity to the inserted particle and reducing the donor mass by the same amount.  It is not yet the full production resampling algorithm: it deliberately filters transfers to unique donor and insertion particles to avoid ambiguous concurrent extraction while validating the mutation kernel.

Run:

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
GRID_CASES='64:64:20 128:128:20' \
bash scripts/run_cuda_resampling_shadow_transfer_smoke_0233.sh
```

Expected:

```text
[0233-resampling-shadow-transfer] PASS 64x64_g20 ...
[0233-resampling-shadow-transfer] PASS 128x128_g20 ...
```

Next step: shadow this primitive on real resampling states, then relax the uniqueness restriction by introducing a donor-cell extraction budget or per-cell compaction of donor particles.
