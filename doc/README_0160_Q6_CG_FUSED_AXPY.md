# 0160 — Q6/CG fused AXPY + residual norm profiling

## Scope

This patch is intentionally narrow and does not change SRC/MPCD physics, Q6
parameters, resampling, boundary conditions, or the elliptic operator stencil.
It keeps the Q6/CG solver fully OpenMP-parallel and does not add a serial
fallback or a new runtime parameter.

The only solver-side optimisation is the CG level-A change agreed after the
0159 profile: in standard iterations, combine

```text
phi += alpha * p
r   -= alpha * Ap
rrNew = dot(r,r)
```

into one OpenMP loop with a reduction on `rrNew`.

When `removePhiMean` triggers its periodic mean-removal path, the code keeps the
previous two-step behaviour: AXPY first, mean removal on `phi` and `r`, then a
separate residual norm. This preserves the original algebraic ordering for
those iterations.

## Files changed or added

```text
src/elliptic_projection.cpp
src/main_src_mpcd_base.cpp
scripts/run_performance_profile_0160.sh
doc/README_0160_Q6_CG_FUSED_AXPY.md
```

## Expected effect

The patch targets the 0159 hot spots:

```text
cg_axpy_phi_residual
cg_dot_residual
```

In the new profile, the fused phase appears as:

```text
cg_axpy_phi_residual_dot
```

The separate dot phase remains available as:

```text
cg_dot_residual_separate
```

It should be near zero except for iterations where mean removal is applied.

## Build

From the repository root, after applying 0156, 0157, 0158 and 0159:

```bash
BUILD_PROFILE=native ./scripts/build_src_mpcd_base_optimized_0156.sh
```

or, for a more portable binary:

```bash
BUILD_PROFILE=release ./scripts/build_src_mpcd_base_optimized_0156.sh
```

## Standard comparison run

```bash
RUN_ROOT=runs/performance_profile_0160 \
THREAD_LIST="1 2 4 8" \
CASE_LIST="classic q6 q6_resampling" \
STEPS=500 \
./scripts/run_performance_profile_0160.sh
```

Outputs:

```text
runs/performance_profile_0160/perf_summary_0160.csv
runs/performance_profile_0160/phase_profile_0160.csv
runs/performance_profile_0160/phase_profile_top_0160.csv
runs/performance_profile_0160/q6_cg_profile_0160.csv
runs/performance_profile_0160/q6_cg_profile_top_0160.csv
```

## Focused Q6 run

```bash
RUN_ROOT=runs/performance_profile_0160_q6_2000 \
THREAD_LIST="1 2 4 8" \
CASE_LIST="q6 q6_resampling" \
STEPS=2000 \
./scripts/run_performance_profile_0160.sh
```

## Validation criteria

Compare against the 0159 outputs:

```text
perf_summary_0159.csv
phase_profile_0159.csv
q6_cg_profile_0159.csv
```

Functional counters should remain coherent:

```text
q6_iterations
resamp_m_rel_rms
resamp_transfer_pairs
resamp_selected_particles
```

Performance criteria:

1. `q6_projection` should not regress.
2. `cg_axpy_phi_residual_dot` should be lower than the combined 0159 cost of
   `cg_axpy_phi_residual + cg_dot_residual`.
3. `cg_dot_residual_separate` should be small, except for mean-removal
   iterations.
4. `cg_apply_operator` is not expected to change significantly in this patch;
   it remains the next target for a future level-C optimisation.
