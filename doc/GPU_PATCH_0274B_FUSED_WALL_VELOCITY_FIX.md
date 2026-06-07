# GPU patch 0274b — fused wall streaming velocity fix

Patch 0274 introduced an optional fused `stream + deposit` path for the CUDA resident periodic and wall-simple classic SRC validators.
The periodic subset passed, but the Poiseuille wall-simple resident rows failed the comparison.

## Cause

The fused wall path reused the active-domain coordinates `domain.yMin` / `domain.yMax` when constructing the wall-frame velocity used by the y-wall reflection.  The standalone wall streaming kernel 0246 uses the active-boundary velocities instead:

- bottom wall velocity: `domain.vyMin + params.wallVpUyBottom`
- top wall velocity: `domain.vyMax + params.wallVpUyTop`

For a static channel, `domain.yMax` is the top wall position, not its velocity.  This made the fused top-wall reflection non-equivalent to 0246 and caused the Poiseuille comparison failure.

## Change

`src/src_collision.cpp` now fills the fused-streaming device config with `domain.vyMin` / `domain.vyMax`, matching `cuda_streaming_wall_simple_0246.cu` and the CPU boundary convention.

## Scope

No CUDA kernel, physics option, validator, Q6 path, resampling path, virial option, or thermostat path is changed.  This is a minimal equivalence fix for 0274 fused wall streaming.

## Validation

Re-run:

```bash
bash scripts/run_cuda_classic_src_resident_perf_0274.sh
```

Expected signal:

- `periodic_0260`: PASS
- `wall_simple_0261`: PASS
- consolidated 0274 validation: PASS
