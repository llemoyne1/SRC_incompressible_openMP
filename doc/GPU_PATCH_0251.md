# GPU patch 0251 — persistent particle/cell state for active cell moments

## Purpose

Patch 0251 targets the main bottleneck observed in 0250: active CUDA cell
moments were functionally correct, but their runtime was dominated by uploading
particle arrays before every cell-moment deposit.

0251 introduces a narrow persistent-state bridge:

- the validated CUDA boundary kernels 0245--0249b now use a single shared
  `CudaParticleState` instead of one private static particle state per module;
- each CUDA boundary kernel marks this shared state as fresh after its device
  mutation and host mirror download;
- CPU boundary/immersed fallbacks invalidate this freshness when they actually
  edit particles;
- active CUDA cell moments can consume the already-current shared particle state
  directly and deposit into a persistent `CudaCellWorkspace`;
- if the shared particle state is not fresh, the code falls back to the 0250
  upload-based cell-moment path.

The CPU state remains authoritative.  This patch does not migrate collision,
thermostat, virial or Q6/Q9.

## New runtime switch

```bash
MPCD_CUDA_CELL_MOMENTS_PERSISTENT_STATE_0251=1
```

When enabled together with `MPCD_CUDA_CELL_MOMENTS_USE=1`, the active
cell-moment step first tries:

```text
shared CudaParticleState -> persistent CudaCellWorkspace -> CPU cell arrays
```

If the shared state has been invalidated by a CPU boundary operation, it safely
uses the previous 0250 path:

```text
host ParticleState upload -> CUDA cell moments -> CPU cell arrays
```

## Expected diagnostic change

For cases where CUDA streaming/boundary is the last particle editor before
collision, the cell-moment active CSV should show:

```text
cellUploadSeconds ~= 0
cellKernelSeconds similar to 0250
cellDownloadSeconds still present
```

Downloads remain necessary because collision/Q6/thermostat are still CPU-side.

For cases with CPU hard-reservoir injection between CUDA inlet/outlet and
collision, the shared state is invalidated and the path falls back; this is
intentional and conservative.

## Validation script

```bash
bash scripts/run_cuda_persistent_cell_state_0251.sh
```

The script compares:

- `cpu_baseline`
- `0250_upload` — active CUDA cell moments with host upload
- `0251_persistent` — active CUDA cell moments from shared persistent state

on the same grouped cases used for 0250:

- `tg_periodic_full`
- `poiseuille_wall_full`
- `open_rect_obstacle_full`
- `piston_virial_full`
- `segmented_u_turn_full`

The expected correctness criterion is unchanged:

```text
verdict=PASS
failed_metrics=0
```

The performance criterion is not global speedup yet; the main metric is the
reduction of `cellUploadSeconds` in fresh-state cases.
