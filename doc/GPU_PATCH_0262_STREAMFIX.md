# GPU patch 0262 streamfix — periodic streaming allowed for solid resident mode

This is a corrective patch for `0262_solid_resident_classic_cuda_no_thermostat`.

## Problem

The resident solid mode enabled CUDA immersed-rectangle reflection and CUDA collision, but the periodic streaming kernel from 0245 still rejected `immersedSolidEnable=true`. As a result, the force/stream phase fell back to CPU on a host `ParticleState` that is intentionally stale between summaries in resident mode. This caused real divergences in momentum/velocity metrics.

## Fix

`src/cuda_streaming_periodic_0245.cu` now treats
`MPCD_CUDA_CLASSIC_SRC_SOLID_RESIDENT_0262=1` as a resident periodic-streaming mode and allows periodic streaming when an immersed solid is present only for that exact 0262 mode.

The sequence becomes:

```text
periodic force/stream CUDA on shared state
→ immersed rectangle CUDA on shared state
→ SRC collision CUDA on shared state
→ summary-only host sync
```

All other immersed-solid configurations remain on the conservative path.
