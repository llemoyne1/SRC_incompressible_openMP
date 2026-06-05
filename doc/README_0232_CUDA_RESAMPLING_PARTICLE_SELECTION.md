# 0232 — CUDA resampling donor-particle selection prototype

This patch starts the transition from non-mutating cell-level resampling diagnostics to particle-level operations.

It adds a standalone CUDA primitive that, for each planned donor-cell transfer, selects a deterministic representative donor particle using the same rule as the CPU validator: the first eligible fluid particle in the donor cell.

The patch does **not** mutate particles yet.  It validates the precondition needed by extraction/insertion:

- every planned donor cell has at least one eligible fluid donor particle;
- CPU and CUDA select the same representative particle;
- eligible donor counts by cell match;
- selected particle masses match to roundoff.

Run:

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
GRID_CASES='64:64:20 128:128:20' \
bash scripts/run_cuda_resampling_particle_select_smoke_0232.sh
```

Expected:

```text
[0232-resampling-particle-select] PASS 64x64_g20 ... missing=0 mismatches=0
[0232-resampling-particle-select] PASS 128x128_g20 ... missing=0 mismatches=0
```

Next step: shadow mutative extraction/insertion on a copied particle state, while preserving mass and momentum invariants before activating CUDA resampling in the real step.
