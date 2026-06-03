# 0164b — profile suffix auto-detection for the 0164 resampling-pool benchmark

This is a script-only correction for the 0164 benchmark runner.

The current executable on the validated OpenMP-optimized branch may write detailed
profile files with a suffix inherited from the last instrumented main file, for
example:

- `phase_profile_0163.csv`
- `q6_cg_profile_0163.csv`

while the 0164 aggregation script originally expected:

- `phase_profile_0161.csv`
- `q6_cg_profile_0161.csv`

The corrected runner now auto-detects the actual suffix produced by the binary
among `0164`, `0163`, `0161`, `0160`, `0159`, `0158`, `0157`, and aggregates the
results into the standard 0164 output names:

- `phase_profile_0164.csv`
- `q6_cg_profile_0164.csv`

No C++ file is modified by this patch.

## Apply

```bash
cd /mnt/e/SRC_MPCD_dev/SRC_openMP_optimized
unzip -o /path/to/SRC_MPCD_openmp_resampling_pool_minimal_0164b_script_fix_files_only.zip
chmod +x scripts/run_performance_profile_0164.sh
```

## Run, resampling-only first

```bash
rm -rf runs/performance_profile_0164_resamp_only
RUN_ROOT=runs/performance_profile_0164_resamp_only \
THREAD_LIST="1 2 4 8" \
CASE_LIST="q6_resampling" \
STEPS=500 \
./scripts/run_performance_profile_0164.sh
```

## Optional: force a suffix if desired

```bash
PROFILE_SOURCE_TAG=0163 ./scripts/run_performance_profile_0164.sh
```
