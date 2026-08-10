# 0493x7k — Q6-g-f production diagnostics stripping

## Purpose

0493x7j removed the dominant host-driven CG synchronization cost.  The remaining
Q6-g-f overhead contained several validation diagnostics that were still executed
every step even though the corresponding x6/x7 physics had already been qualified.

0493x7k removes those diagnostics from the hot path without changing the Q6-g-f
operator, force ordering, phase geometry, pressure interface condition, density
relaxation RHS, B1 face-to-particle reconstruction, or convergence criterion.

There is no new user parameter or runtime flag.  `summaryEvery` is reused as the
existing diagnostic cadence.

## Production cadence

For `free_surface_masked` / Q6-g-f, the expensive non-failure diagnostics run only
when

```text
step <= 1 || step % max(1, summaryEvery) == 0
```

Failure-only x6f-d1/d2 diagnostics remain unconditional on solver failure.
Historical `independent_masked` behavior outside the free-surface Q6-g-f path is
left unchanged.

## Removed from non-summary Q6-g-f steps

The following work is skipped between summary steps:

- correction RMS/max block reductions and host downloads;
- projected-face divergence audit kernel and its three scalar reductions;
- Q6 correction momentum audit and corrected-particle count reductions in the
  fused free-surface particle-apply kernels;
- the 0493w6 post-application species reset/deposit/finalize that existed to
  reconstruct the applied-cell divergence diagnostic;
- the post-application divergence reconstruction/reductions;
- per-step `cuda_species_q6_independent_masked_0493w5.csv` append;
- per-step `cuda_species_q6_0491.csv` append.

The two CSVs now contain step 1 and summary-cadence rows for Q6-g-f.  Their final
row therefore remains the final simulation step when `summaryEvery` divides the
run length, as in the qualification runners.

## Work retained every step

The production physics and safety path remains unchanged:

- carrier/support mask construction and free-surface regularization;
- x6c raw liquid fill and filtered alpha geometry;
- x6f pressure mask and prepared face coefficients;
- x6g interfacial gas-pressure contribution;
- x7d density-restoration RHS;
- x7j fully CUDA-resident CG and convergence test;
- face correction, patch-A low-wall reconstruction and B1 RT0 particle apply;
- force-before-streaming Q6-G ordering;
- general corrected cell-moment rebuild used by the subsequent resident pipeline;
- active-domain zero-support guards and all solver-failure diagnostics.

The x6c/x6f/x6g geometry/interface audits were already summary-cadence and keep
that behavior.

## Virial compatibility

The legacy experimental virial-density path keeps the 0493w6 post-application
species observation point on every step.  Q6-g-f production uses x7d with virial
off, so this preservation does not affect the target production path.

## Expected validation

1. Build `build/src_mpcd_base_cuda_q6_resident_livevis_0486`.
2. Run a 100-step TG smoke with `summaryEvery=20` and verify the final q6F/q6A,
   CG convergence, and x7j resident-CG columns.
3. Repeat the 1000-step TG benchmark at `projectionTolerance=1e-5` and compare
   physical end-state summaries against x7j.
4. Run one dynamic liquid-gas dam-break smoke to ensure that the true interface
   path still reports x6c/x6f/x6g diagnostics at summary cadence.
5. Re-run x7f/x7g multibc/Darcy qualification if the performance smoke is clean.
