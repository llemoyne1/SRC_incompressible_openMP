# 0360 - Darcy / CUDA resampling compatibility by chi filtering

## Rationale

The Darcy/topology branch uses `chi=1` for fluid and `chi=0` for solid/penalized regions. Resampling and empty-refill must not create or modify particles in cells that are topologically solid, otherwise the particle population can pollute the penalized region and corrupt the physical interpretation of the Darcy field.

The compatibility rule added here is local and conservative: when Darcy/Brinkman is enabled, CUDA 0296 mass reconditioning, CUDA 0297 split/merge, and CUDA 0319 empty-refill skip any cell whose device `chi` is below `cudaResamplingChiMin`. The default threshold is `0.5` and the default guard is enabled.

## Implementation

Parameters:

- `cudaResamplingChiFilterEnable = true`
- `cudaResamplingChiMin = 0.5`
- aliases accepted for older naming: `cudaResamplingDarcyChiFilterEnable`, `cudaResamplingDarcyChiMin`

Efficiency points:

- The filter reuses the resident Darcy `d_chi` field through `cuda_darcy_brinkman_0343_device_chi_field`.
- No CPU-side chi copy is introduced in the resampling path.
- Kernels branch once per cell or per particle using the already resident cell id and `chi[c]`.
- Empty-refill memory, candidate selection, particle creation, and post-refill conservation scaling are all limited to chi-allowed cells.

The historical Darcy validation guard no longer rejects resampling unconditionally. It still rejects `darcyBrinkmanEnable=true` with top-level `resamplingEnable=true` unless the chi filter is enabled. The recommended path remains CUDA-resident resampling through `TOPO_RESAMPLING_ENABLE=1`, leaving top-level weighted resampling disabled.

## Validation Performed

Builds:

- `build/src_mpcd_base_cuda_darcy_resamp_0360` with topo Darcy + livevis + CUDA resampling.
- `build/src_mpcd_base_cuda_empty_refill_0319b` without Darcy, to verify the Darcy hook is optional.

Smoke case:

- NACA0012, AoA 18 deg, `120x32`, gamma 6, 80 steps, livevis disabled.
- Last resampling step: `chiFilterEnable=1`, `chiMin=0.5`, `excludedChiCells=30`, `chiSkippedParticles=202`.

Visible case:

- NACA0012, AoA 18 deg, `180x48`, gamma 6, 200 steps, livevis enabled, field `mass`.
- Last resampling step: `excludedChiCells=72`, `chiSkippedParticles=709`, `appliedParticles=581`.
- 0297 total time at last step: about `0.00464 s`; 0296 total time: about `0.00159 s`.

## Validation Script

Use:

```bash
BIN=build/src_mpcd_base_cuda_darcy_resamp_0360 LIVE_VIS_ENABLE=1 LIVE_VIS_FIELD=mass bash scripts/run_topo_darcy_naca_resampling_livevis_0360.sh
```

The script runs two sequential cases with the same seed and chi field:

1. `classic`: Darcy only.
2. `resampling_refill`: Darcy + CUDA 0296/0297/refill with chi filtering.

## Current Limits

This is a numerical compatibility fix, not yet a full physics validation of high-incidence NACA behavior. The short livevis run confirms sequencing, diagnostics, and resident CUDA execution. A longer run is still needed to quantify whether empty-refill improves persistent depleted wake/pocket regions without biasing the Darcy force statistics.
