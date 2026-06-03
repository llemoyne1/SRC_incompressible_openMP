# 0167b — Mass-guard buffer-only optimization

This differential patch is intentionally narrower than the rejected 0167 fast-path patch.

It only changes `src/weighted_resampling.cpp` inside `apply_resampling_particle_mass_guards`:

- `oldMass` and `newMass` are allocated once outside the serial cell loop;
- each cell reuses those buffers via `assign(ids.size(), 0.0)`;
- the bounded projection, velocity recenter/rescale, state write-back, diagnostics, and residual calculations remain on the same path for every feasible wet cell.

No fast path is introduced. No guarded cell is skipped. The purpose is to test whether removing per-cell vector allocations provides a small performance benefit while preserving the exact discrete resampling trajectory.

## Apply

```bash
cd SRC_openMP_optimized
unzip -o SRC_MPCD_openmp_mass_guard_buffer_only_0167b_files_only.zip
chmod +x scripts/run_performance_profile_0167b.sh
```

## Build

```bash
BUILD_PROFILE=native ./scripts/build_src_mpcd_base_optimized_0156.sh
```

## Profile run

```bash
RUN_ROOT=runs/performance_profile_0167b_resamp_guard \
THREAD_LIST="1 2 4 8" \
CASE_LIST="q6_resampling" \
STEPS=500 \
./scripts/run_performance_profile_0167b.sh
```

## Discriminating validation

If the profile is acceptable, repeat the mono-configuration validation used after 0167. This patch should pass the strict comparison more easily than 0167 because it does not skip the mass-guard projection path.
