# 0200 — CUDA cell-moments shadow validation inside the real SRC/MPCD step

This patch promotes the 0199 standalone CUDA particle-to-cell deposit prototype to
an in-step **shadow validation** mode.

The CPU/OpenMP collision deposit remains the only path used by the dynamics.  When
compiled with `MPCD_ENABLE_CUDA_CELL_MOMENTS` and run with
`MPCD_CUDA_CELL_MOMENTS_SHADOW=1`, the collision step additionally recomputes the
real-particle cell moments with CUDA immediately after the CPU thread-local deposit
and before virtual-particle wall/immersed-solid contributions are added.

The compared quantities are therefore the real-particle pre-wall moments:

- `cellId[i]`, with `-1` for non-fluid particles;
- real-particle `cellCount[c]`;
- real-particle `cellMass[c]`;
- real-particle momentum sums `cellPx[c]`, `cellPy[c]`;
- real-particle mean velocities `cellUx[c]`, `cellUy[c]`.

Virtual-particle wall augmentation is deliberately excluded from this comparison.
That keeps the first CUDA deposit validation independent of the thermal wall RNG,
immersed-solid area fractions, and wallVP diagnostics.

## Runtime switches

The mode is off by default.

```bash
MPCD_CUDA_CELL_MOMENTS_SHADOW=1
MPCD_CUDA_CELL_MOMENTS_SHADOW_EVERY=1
MPCD_CUDA_CELL_MOMENTS_SHADOW_STRICT=1
MPCD_CUDA_CELL_MOMENTS_SHADOW_TOL=1e-9
MPCD_CUDA_CELL_MOMENTS_THREADS_PER_BLOCK=256
```

If strict mode is enabled, any cell id/count mismatch or any moment discrepancy
larger than the tolerance aborts the run.  Otherwise the per-step diagnostics are
only written to CSV.

The per-case shadow CSV is:

```text
<case-output-dir>/cuda_cell_moments_shadow_0200.csv
```

## Build

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' bash scripts/build_src_mpcd_cuda_0200.sh
```

## Validation script

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
GRID_CASES='64:200 128:100' \
CASE_LIST='tg_periodic_full' \
PROJECTION_BACKEND=cpu \
bash scripts/run_cuda_cell_moments_shadow_0200.sh
```

The aggregate CSV is:

```text
dev_history/artifacts/gpu_cuda_deposit_0200/cuda_cell_moments_shadow_0200.csv
```

If `RUN_BASELINE=1`, the script also runs the same case without shadow mode and
compares baseline vs shadow runtime summaries to verify that shadow validation does
not modify the dynamics.

## Scope and limitations

- Dynamics still use CPU/OpenMP deposit.
- CUDA deposit is not yet used by collision, thermostat, Q6, or resampling.
- The prototype still uploads particle arrays and downloads full cell arrays at
each shadow call.  That is intentionally diagnostic, not final-performance code.
- The next performance-oriented step should introduce a persistent CUDA deposit
context and then test whether the CUDA cell moments can replace the CPU deposit in
TG periodic mode.
