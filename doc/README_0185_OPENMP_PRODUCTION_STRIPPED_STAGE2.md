# 0185 — openmp-production-stripped, stage 2

This stage removes the dead internal profiling scaffolding that remained after
0184.  It does not remove fluid-mechanics diagnostics, runtime summaries, state
or field dumps, Q6 residual summaries, resampling global counters, or
virial/capacity diagnostics.

Removed from `src/` and `include/`:

- `StepProfile` and `step_profile_phase_name()`;
- `Q6ProjectionProfile` and `q6_projection_profile_phase_name()`;
- `EllipticProjectionProfile` and `elliptic_projection_profile_phase_name()`;
- `ResamplingPopulationGuardProfile`, `ResamplingMassGuardProfile`,
  deposit-profile phase/context labels and corresponding phase-name helpers;
- all `MPCD_*_PROFILE(...)` no-op macros;
- `ResamplingDepositProfileContext` and profiling-only deposit context arguments;
- profiling-only fields such as `populationGuardProfileSeconds`,
  `massGuardProfileSeconds`, `depositProfileSeconds`, and related deposit-profile
  metadata.

Kept intentionally:

- `RuntimeSummaryWriter` and `summary_runtime.csv`;
- mass, active-particle count, momentum, temperature and `kBT` summaries;
- Q6/elliptic physical convergence diagnostics, including iterations,
  residuals, divergence and correction/projected-flux RMS metrics;
- global resampling diagnostics that describe the algorithmic state of the
  fluid calculation, including population/mass guard counters and remap/thermal
  renormalization counters;
- virial/capacity/wall-pressure diagnostics when enabled;
- dumps required for MATLAB or other post-processing.

## Apply after 0184

```bash
cd /mnt/e/SRC_MPCD_dev/SRC_openMP_production_stripped
unzip -o /mnt/c/Users/llemoyne/Downloads/openmp_production_stripped_stage2_0185_files_only.zip
chmod +x scripts/run_openmp_production_stripped_smoke_0185.sh
chmod +x scripts/run_openmp_production_stripped_validation_0185.sh
chmod +x scripts/audit_openmp_production_stripped_0185.sh
```

## Build and smoke test

```bash
BUILD_PROFILE=safe bash scripts/build_src_mpcd_base_optimized_0156.sh

THREADS=4 \
STEPS=50 \
SUMMARY_EVERY=10 \
RUN_ROOT=runs/openmp_production_stripped_smoke_0185 \
RUN_TAG=production_stripped_0185 \
bash scripts/run_openmp_production_stripped_smoke_0185.sh

bash scripts/audit_openmp_production_stripped_0185.sh runs/openmp_production_stripped_smoke_0185
```

The audit uses portable `grep`/`find`; it does not require `rg`.

## Stage-1 vs stage-2 comparison

Assuming the 0184 checkout is available as `../SRC_openMP_production_stripped_0184`:

```bash
THREADS=8 \
STEPS=1000 \
SUMMARY_EVERY=100 \
REF_ROOT=../SRC_openMP_production_stripped_0184 \
RUN_ROOT_REF=runs/validation_0185_stage1_ref \
RUN_ROOT_STRIPPED=runs/validation_0185_stage2_stripped \
bash scripts/run_openmp_production_stripped_validation_0185.sh

cat validation_compare_summary_0185.csv
```

Expected verdict: `PASS` on the four validation cases:

- `tg_periodic_full`;
- `poiseuille_wall_full`;
- `open_rect_obstacle_full`;
- `piston_virial_full`.

## Notes

The deposit refresh path keeps the `reuseExistingCellIds` optimization.  The
removed `ResamplingDepositProfileContext::PostGuard` label was profiling-only;
the production behavior is now expressed directly by the explicit boolean
`reuseExistingCellIds` argument.
