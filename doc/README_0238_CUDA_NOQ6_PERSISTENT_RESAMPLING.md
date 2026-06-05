# 0238 — Combined no-Q6 persistent CUDA + resampling harness

This patch does not add a new numerical kernel.  It composes the validated
persistent particle/cell SRC+thermostat path with the active CUDA resampling
extraction+insertion path.

The target is the SRC/MPCD incompressible chantier without Q6 projection.  Q6 is
left disabled so that the effect of the particle/resampling GPU stack can be
measured without the elliptic CG bottleneck.

## Modes

The harness compares:

- `cpu_baseline`: CPU/OpenMP reference;
- `shared_particle_cell_workspace`: persistent CUDA deposit + SRC collision + thermostat;
- `cuda_resampling_extract_insert`: CUDA resampling extraction+insertion with CPU SRC path;
- `combined_persistent_resampling`: persistent CUDA SRC+thermostat plus CUDA extraction+insertion.

The combined mode enables:

```bash
MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE=1
MPCD_CUDA_PERSISTENT_PARTICLE_STATE_USE=1
MPCD_CUDA_PERSISTENT_PARTICLE_METADATA_CACHE=1
MPCD_CUDA_PERSISTENT_CELL_WORKSPACE_USE=1
MPCD_CUDA_RESAMPLING_EXTRACTION_USE=1
MPCD_CUDA_RESAMPLING_INSERTION_USE=1
```

## Validation

```bash
CUDA_ARCH_FLAGS='-arch=sm_89' \
GRID_CASES='64:200 128:100' \
PROJECTION_ENABLE=false \
bash scripts/run_cuda_noq6_persistent_resampling_0238.sh
```

The main output is:

```text
dev_history/artifacts/gpu_cuda_resampling_0238/cuda_noq6_persistent_resampling_0238.csv
```

Acceptance criteria:

- `verdict = PASS` for every CUDA mode;
- `failed_metrics = 0`;
- `combined_persistent_resampling` should not degrade the physics summaries;
- performance is interpreted relative to `cpu_baseline`.

## Rationale

Patch 0237 showed that active CUDA resampling extraction+insertion can produce a
large gain in isolation.  Patch 0225 showed that persistent particle/cell state
also improves the no-Q6 path.  This harness checks whether both gains compose in
the real validation pipeline before moving resampling mutations directly onto
`CudaParticleState`.
