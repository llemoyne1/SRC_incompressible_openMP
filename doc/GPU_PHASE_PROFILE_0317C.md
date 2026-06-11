# GPU phase profile 0317c

This is a script-only profiling harness. It does not modify the solver.

Motivation: on the 0317b run, Nsight Systems generated `.qdstrm` traces but failed to import/export CSV statistics because the Nsight importer binary/dependencies were missing. Therefore the kernel/API tables remained empty. The 0317b external timings and the existing `cuda_persistent_src_collision_thermostat_0215.csv` already show that the persistent SRC collision/thermostat CUDA section accounts for only a minority of the `src_cuda_v2` wall time. 0317c narrows the remaining unaccounted time using existing opt-in profilers.

Generated outputs:

- `gpu_phase_profile_0317c_summary.csv`
- `gpu_phase_profile_0317c_src_phase_breakdown.csv`
- `gpu_phase_profile_0317c_cuda_resident_breakdown.csv`
- per-run logs and `/usr/bin/time` CSVs

Default targets:

- `src_cuda_v2_0315m_periodic`: reproduces the existing 0285 periodic cylinder runner.
- `src_cuda_v2_0315m_io`: direct inlet/outlet VK-like SRC case with `bcLeft=inlet`, `bcRight=outlet`.
- `mpcd_vkkh_play`: standalone comparison code.

Typical use:

```bash
cd /mnt/e/SRC_MPCD_dev/SRC_GPU
unzip -o /path/to/gpu_phase_profile_0317c_files_only.zip -d .
cp /path/to/mpcd_vkkh_play.cu ./mpcd_vkkh_play.cu

STEPS=10000 WARMUP_STEPS=1000 REPEATS=1 INACTIVE_SLOTS=100000 \
  bash scripts/run_gpu_phase_profile_0317c.sh
```

Zip results:

```bash
cd /mnt/e/SRC_MPCD_dev/SRC_GPU
zip -r gpu_phase_profile_0317c_results.zip \
  dev_history/artifacts/gpu_phase_profile_0317c
```

Normal production runs are unaffected: `MPCD_INTERNAL_PROFILES=1` and `MPCD_CUDA_RESIDENT_PROFILE_0266=1` are set only inside this profiling harness unless overridden.
