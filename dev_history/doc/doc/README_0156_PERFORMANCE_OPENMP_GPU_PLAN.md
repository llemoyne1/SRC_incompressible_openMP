# 0156 — Performance roadmap: OpenMP first, GPU second

This step starts from the 0152/0155 C++/OpenMP code state and does not change the physical model: SRC streaming/collision, Q6 projection, Q9/resampling, virial closure, wallVP, open boundaries and immersed-solid handling remain the reference functionality.

## Initial local probe

A compact Taylor--Green probe was run with the existing executable on a 64 x 64, gamma=20, 40-step case. The absolute timings are machine-dependent, but the trend is informative:

| case | 1 thread | 2 threads | 4 threads | 8 threads | observation |
|---|---:|---:|---:|---:|---|
| classic | 1.28 s | 1.02 s | 0.97 s | 1.37 s | modest scaling, slowdown at 8 threads |
| q6 | 2.57 s | 2.43 s | 2.84 s | 3.23 s | Q6 CG is barrier/reduction dominated at this size |
| q6_resampling | 4.64 s | 3.70 s | 3.43 s | 3.19 s | resampling gains a little, still far from ideal |

For this probe, `q6Iterations=140`, while `resampTransferPairs=0` and `resampSelectedDonorParticles=0`. Thus, on an exactly populated periodic case, the extra resampling cost is not dominated by donor/receiver transfer planning; it is dominated by deposit/remap/thermal-renormalization passes and diagnostics.

## OpenMP optimization order

1. Establish reproducible timing baselines with `scripts/run_performance_probe_0156.sh` for `classic`, `q6`, and `q6_resampling`, with `THREAD_LIST="1 2 4 8 16"` when enough cores are available.
2. Separate compiler effects from algorithmic effects using `scripts/build_src_mpcd_base_optimized_0156.sh` with `BUILD_PROFILE=safe`, `release`, `native`, and optionally `lto-native`.
3. Optimize the particle-dominated passes first: thermal renormalization, mass remap, diagnostics and repeated deposits.
4. Then optimize the CG projection path: reduce the number of OpenMP regions per CG iteration, fuse vector kernels where possible, and reuse workspaces to avoid repeated allocation/fill costs.
5. Re-check open-boundary and immersed-solid cases only after the periodic Taylor--Green probe scales correctly.

## Code change in this patch

`apply_resampling_local_thermal_renormalization` now uses per-thread cell accumulators for its two particle scans when `Np > 10000`:

- current thermal energy / mass / momentum before renormalization;
- velocity update plus post-renormalization momentum accumulation.

This avoids serial O(Np) passes in the thermal resampling path while keeping the same cell-level operation and diagnostics. Floating-point summation order changes in parallel mode, so exact bitwise equality should not be expected; physical and diagnostic tolerances should be used.

## GPU direction

The GPU route should not start by porting the full current code. The suitable order is:

1. particle streaming and cell-id deposit kernels;
2. cell reductions and SRC collision;
3. thermostat/remap kernels;
4. Q6/Q9 stencil operators and CG vector kernels;
5. boundary/immersed-solid special cases only after the bulk kernels are stable.

A CUDA implementation is the most direct path for the current SoA particle layout. OpenMP target can be evaluated later, but only after the CPU OpenMP version has been cleaned enough to expose coarse kernels with explicit workspaces and limited host-side branching.

## Validation commands

```bash
./scripts/build_src_mpcd_base_optimized_0156.sh
./build/validate_elliptic_projection
THREAD_LIST="1 2 4 8" CASE_LIST="classic q6 q6_resampling" \
  ./scripts/run_performance_probe_0156.sh
```

Then compare `runs/performance_probe_0156/perf_summary_0156.csv` against the previous executable or previous commit.
