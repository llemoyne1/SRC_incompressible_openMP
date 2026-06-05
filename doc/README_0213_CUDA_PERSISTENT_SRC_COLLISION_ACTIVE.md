# 0213 — CUDA persistent particle state, active SRC collision subset

This patch starts the real migration toward a persistent GPU particle state.
It does **not** yet move the full SRC/MPCD step to the GPU. Instead, it replaces
the collision phase by one CUDA substep that keeps particle arrays resident while
performing:

```text
upload x/y/vx/vy/mass/role once
  -> particle-to-cell deposit
  -> cell velocity finalization
  -> SRC rotation
  -> download vx/vy and cellId once
```

The downstream CPU stages are unchanged:

```text
Q6 projection
closed-capacity / virial kick
cell-relative thermostat
resampling
summaries / dumps
```

## Runtime flag

The path is disabled by default. Enable it with:

```bash
MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=1
```

The current supported subset is deliberately narrow:

- periodic x and periodic y;
- full-domain fluid bounds;
- no immersed solid;
- no wall virtual-particle coupling;
- one CUDA collision substep per SRC/MPCD step;
- CPU Q6/thermostat/resampling kept unchanged.

Unsupported cases fail explicitly by default. To request fallback instead of an
exception:

```bash
MPCD_CUDA_PERSISTENT_SRC_COLLISION_STRICT=0
```

## Why this patch exists

Previous patches validated separate CUDA kernels for cell moments, SRC collision,
and thermostat. Their main limitation was repeated host/device transfers. 0213
combines deposit and SRC rotation behind a single upload/download boundary and
returns the `cellId` array needed by the existing CPU thermostat.

This is the first active integration step toward a true persistent GPU particle
state. The next stages should either extend the resident sequence to the
thermostat/Q6 ordering or introduce a persistent context that survives across
multiple phases of the real step.

## Validation

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
GRID_CASES='64:200 128:100' \
PROJECTION_BACKEND=cpu \
bash scripts/run_cuda_persistent_src_collision_active_0213.sh
```

The harness compares:

```text
baseline CPU collision
active persistent CUDA deposit+SRC collision
```

Expected consolidated output:

```text
dev_history/artifacts/gpu_cuda_persistent_0213/cuda_persistent_src_collision_active_0213.csv
```

Criteria:

- `verdict = PASS`;
- `failed_metrics = 0`;
- `invalidCellParticles = 0`;
- physical summaries remain within the existing 0162 validation tolerances.
