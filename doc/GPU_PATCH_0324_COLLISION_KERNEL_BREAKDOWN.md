# GPU patch 0324 — internal collision kernel breakdown

## Purpose

The external 0323 kernel microprofile did not produce kernel rows on the
workstation:

- `ncu` connected to `src_cuda_v2`, but failed with `ERR_NVGPUCTRPERM`.
- `mpcd_vkkh_play` rejected the `--out` argument used by the script wrapper.

Patch 0324 therefore adds a **disabled-by-default** internal CUDA-event
breakdown for the persistent `collision+thermostat` kernel batch only.

This is a profiling patch, not an optimization patch.

## Runtime flags

The instrumentation is off by default.

Enable it with:

```bash
SRC_GPU_KERNEL_BREAKDOWN_0324=1
```

The runner maps this to:

```bash
MPCD_CUDA_PERSISTENT_SRC_COLLISION_KERNEL_BREAKDOWN_0324=1
MPCD_CUDA_PERSISTENT_SRC_COLLISION_KERNEL_BREAKDOWN_0324_FILE=<OUT_DIR>/cuda_persistent_kernel_breakdown_0324.csv
```

The code synchronizes around each instrumented kernel launch when enabled, so
use short runs only, e.g. 300 or 500 steps.

## Output

Per-launch rows:

```text
<run>/output/cuda_persistent_kernel_breakdown_0324.csv
```

Aggregated summary:

```text
dev_history/artifacts/gpu_phase_profile_0317d/gpu_collision_kernel_breakdown_0324_top_kernels.csv
```

Generate the aggregate with:

```bash
python3 scripts/summarize_gpu_collision_kernel_breakdown_0324.py
```

## Instrumented kernels

- `setup_fill_rotation_tables_0272`
- `reset_persistent_cells`
- `deposit_persistent`
- `add_wall_virtual_faces_persistent`
- `finalize_velocity_persistent`
- `src_rotate_persistent`
- `reset_thermostat_real_moments_0276`
- `deposit_thermostat_real_moments_0276`
- `kinetic_persistent`
- `scale_persistent`
- `apply_thermostat_persistent`

`finalize_velocity_persistent` appears twice per cycle and is aggregated under
the same label.

## Decision rule

Only after this profile identifies a dominant kernel should the next patch
target either:

- the dominant kernel implementation,
- launch fusion,
- or precision/atomic behavior.

Do not restart the float chantier unless this profile specifically shows that
the double/atomic-heavy kernels dominate the remaining time.
