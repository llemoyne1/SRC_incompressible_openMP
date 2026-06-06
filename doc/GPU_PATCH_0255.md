# GPU patch 0255 — persistent SRC collision for piston / closed-capacity wall case

## Scope

Patch 0255 extends the persistent CUDA SRC collision path validated in 0252--0254 to the piston/closed-capacity wall subset used by `piston_virial_full`.

Validated target:

- case: `piston_virial_full`
- geometry: periodic in `x`, bounded in `y`, moving/compressing top-wall domain through `FluidDomainBounds`
- CUDA boundary stack: resampling 0244, piston streaming 0247b, persistent cell state 0251
- CUDA collision: persistent SRC collision consuming the shared 0251 particle state and cell workspace
- CPU: Q6/Q9 projection, virial closed-capacity response, thermostat, diagnostics

## Deliberate restrictions

The CUDA collision branch is enabled only when:

- `MPCD_CUDA_PERSISTENT_SRC_COLLISION_PISTON_0255=1`
- `closedCapacityResponseEnable=true`
- periodic `x`, bounded `y`
- bottom/top wall coupling is enabled
- left/right wall coupling is absent
- `wallThermalNoise=0`
- no immersed solid is active

Thermal wall noise, collision+thermostat fusion, virial kick fusion and Q6/Q9 GPU projection remain future steps.

## Algorithmic point

The 0253 wall-simple CUDA collision already carries deterministic virtual-wall mass/momentum. Patch 0255 relaxes the previous full-domain restriction for the piston subset, allowing the device collision to consume the time-dependent `FluidDomainBounds` used by the CPU path. The top-wall velocity is passed through the existing wall-velocity configuration fields.

## Validation

Run:

```bash
bash scripts/run_cuda_persistent_src_collision_piston_0255.sh
```

Default validation:

```text
piston_virial_full
64x64_s300
128x128_s300
```

Compared modes:

```text
cpu_baseline
0251_persistent_cell_moments_piston
0255_persistent_src_collision_piston_shared
```

Expected criterion:

```text
verdict=PASS
failed_metrics=0
collisionActiveCalls > 0
collisionSharedParticleStateFraction = 1
collisionSharedCellWorkspaceFraction = 1
collisionParticleStateUploadSeconds = 0
```

Output:

```text
dev_history/artifacts/gpu_cuda_src_collision_0255/cuda_persistent_src_collision_0255.csv
```
