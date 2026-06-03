# 0161 — Precompiled elliptic operator plan for Q6/CG

This patch is the first ambitious but controlled optimization of the Q6 elliptic
CG operator after the 0158 hotspot cleanup and the 0160 fused residual update.
It does not add a serial small-grid mode, does not add a user-facing parameter,
and does not change the physical projection model.

## Main changes

1. A general `EllipticOperatorPlan` is added to `EllipticProjectionWorkspace`.
   The plan is rebuilt once per elliptic solve from the current grid, boundary
   conditions, active-cell mask, and face coefficients `alpha`.

2. The plan stores active and inactive cells and four branchless neighbor/face
   entries per active cell. Missing, closed, or solid-cut faces are encoded by a
   zero coefficient and a self-neighbor. This moves boundary/mask logic out of
   the hot CG iteration loop.

3. The CG operator application now uses
   `apply_elliptic_operator_plan_and_dot`, which computes both `Ap = A*p` and
   `pAp = dot(p, Ap)` in one pass over active cells.

4. The previous public `apply_elliptic_operator(...)` remains available and is
   still used by non-Q6 paths such as the Helmholtz low-pass operator. The new
   optimized path is confined to the Q6/CG solve.

## Expected effects

The old 0160 profile separated:

- `cg_apply_operator_dot_pAp` (operator application after prior AXPY fusion),
- plus a legacy zero `cg_dot_pAp` slot.

In 0161, `cg_apply_operator_dot_pAp` should include the branchless precompiled
operator application and the fused `pAp` reduction. A new phase,
`cg_operator_plan_build`, reports the one-time stencil construction cost per Q6
solve.

The patch is designed to help not only periodic Taylor-Green cases but also
inlet/outlet and immersed-solid cases, because the costly mask/boundary tests
are encoded once in the operator plan rather than repeated at every CG
iteration.

## Validation commands

Apply this archive after 0160:

```bash
unzip -o SRC_MPCD_openmp_elliptic_plan_0161_files_only.zip
chmod +x scripts/run_performance_profile_0161.sh
```

Build:

```bash
BUILD_PROFILE=native ./scripts/build_src_mpcd_base_optimized_0156.sh
```

Run the standard benchmark:

```bash
RUN_ROOT=runs/performance_profile_0161 \
THREAD_LIST="1 2 4 8" \
CASE_LIST="classic q6 q6_resampling" \
STEPS=500 \
./scripts/run_performance_profile_0161.sh
```

Useful outputs:

```text
runs/performance_profile_0161/perf_summary_0161.csv
runs/performance_profile_0161/phase_profile_0161.csv
runs/performance_profile_0161/phase_profile_top_0161.csv
runs/performance_profile_0161/q6_cg_profile_0161.csv
runs/performance_profile_0161/q6_cg_profile_top_0161.csv
```

## Physical checks

Compare against 0160 for:

- `q6Iterations`,
- `q6DivAfterProjectedFluxRms`,
- `q6ResidualRel`,
- `resampMRelRms`,
- `resampTransferPairs`,
- `resampSelectedDonorParticles`.

Small last-bit differences are possible because reductions are fused and the
operator application order is slightly reorganized. The accepted criterion is
unchanged physical diagnostics and comparable convergence behavior.
