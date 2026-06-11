# GPU phase profile 0317d

This is a script-only profiling harness. It does not modify the solver.

Motivation: on the 0317b run, Nsight Systems generated `.qdstrm` traces but failed to import/export CSV statistics because the Nsight importer binary/dependencies were missing. Therefore the kernel/API tables remained empty. The 0317b external timings and the existing `cuda_persistent_src_collision_thermostat_0215.csv` already show that the persistent SRC collision/thermostat CUDA section accounts for only a minority of the `src_cuda_v2` wall time. 0317d narrows the remaining unaccounted time using existing opt-in profilers.

Generated outputs:

- `gpu_phase_profile_0317d_summary.csv`
- `gpu_phase_profile_0317d_src_phase_breakdown.csv`
- `gpu_phase_profile_0317d_cuda_resident_breakdown.csv`
- per-run logs and `/usr/bin/time` CSVs

Default targets:

- `src_cuda_v2_0315m_periodic`: reproduces the existing 0285 periodic cylinder runner.
- `src_cuda_v2_0315m_io`: direct inlet/outlet VK-like SRC case with `bcLeft=inlet`, `bcRight=outlet`.
- `mpcd_vkkh_play`: standalone comparison code.

Typical use:

```bash
cd /mnt/e/SRC_MPCD_dev/SRC_GPU
unzip -o /path/to/gpu_phase_profile_0317d_files_only.zip -d .
cp /path/to/mpcd_vkkh_play.cu ./mpcd_vkkh_play.cu

STEPS=10000 WARMUP_STEPS=1000 REPEATS=1 INACTIVE_SLOTS=100000 \
  bash scripts/run_gpu_phase_profile_0317d.sh
```

Zip results:

```bash
cd /mnt/e/SRC_MPCD_dev/SRC_GPU
zip -r gpu_phase_profile_0317d_results.zip \
  dev_history/artifacts/gpu_phase_profile_0317d
```

Normal production runs are unaffected: `MPCD_INTERNAL_PROFILES=1` and `MPCD_CUDA_RESIDENT_PROFILE_0266=1` are set only inside this profiling harness unless overridden.


## Correctif 0317d

Ce harnais corrige l’arrêt `STATE_FILE: unbound variable` observé dans le générateur du helper inlet/outlet 0317c. Le correctif est script-only et ne modifie pas le solveur. Par défaut, `SRC_BUILD=0` et `VKKH_BUILD=0` afin d’éviter une recompilation lors de la relance après un build déjà effectué.

Par défaut, le script réutilise `build/mpcd_vkkh_play_0317c` afin d’éviter de recompiler VKKH après un run 0317c déjà lancé.
