# 0445 — in-solver CUDA resampling clean-pipeline shadow hook

This patch introduces the experimental runtime flag:

```bash
MPCD_CUDA_RESAMPLING_PIPELINE_SHADOW_0445=1
```

The hook is non-mutating: the existing CPU resampling path remains authoritative.  It
captures the particle state immediately before the CPU remap/thermal phase, lets the
CPU path run as usual, then replays the clean remap+thermal phase on CUDA and compares
the resulting device-shadow state to the CPU final state.

The initial integrated hook is intentionally limited to the clean periodic validation
profile where no extraction/insertion transfer plan is active.  Non-empty transfer
plans are skipped and still remain covered by the standalone validators:

- 0439 deposit/classification
- 0440 poor/rich compaction
- 0441 transfer planner
- 0442 particle extraction/insertion apply
- 0443 remap + thermal
- 0444 end-to-end clean pipeline

## Outputs

When enabled, the hook appends:

```text
<outputDir>/cuda_resampling_pipeline_shadow_0445.csv
```

The relevant columns are:

- `handled`, `pass`, `skipped`, `skipReason`
- `planEntries`, `passiveOps`
- `cpuRemapCells`, `gpuRemapCells`
- `cpuThermalCells`, `gpuThermalCells`
- `roleMismatch`, `badPrefixCpu`, `badPrefixGpu`
- `maxAbsMass`, `maxAbsVx`, `maxAbsVy`
- `massCpu/massGpu`, `pxCpu/pxGpu`, `pyCpu/pyGpu`, `keCpu/keGpu`

## Expected clean validation result

For the 0438H clean periodic shear/TG profile, the expected result is:

```text
handled=1
pass=1
skipped=0
passiveOps=0
roleMismatch=0
badPrefixCpu=0
badPrefixGpu=0
maxAbs* at roundoff
```

No production resampling semantics are changed by this patch.
