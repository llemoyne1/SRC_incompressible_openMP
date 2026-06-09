# 0314 — Compact Fluid-only summaries and dumps for large inactive reservoirs

## Motivation

Long CUDA-resident resampling runs may need a large pool of `role=Inactive`
particle slots.  These slots should not participate in the physics, but they can
still become expensive when host-side summaries or `.smpcd` dumps download and
write the whole particle capacity.

Patch 0314 adds an optional compact path for visualization/diagnostic outputs:
only `role=Fluid` particles are downloaded/written when requested.  The legacy
full-state behavior remains the default.

## New parameters

```text
dumpRoleFilter = all | fluid
summaryRoleFilter = all | fluid
```

Defaults:

```text
dumpRoleFilter = all
summaryRoleFilter = all
```

`all` preserves the previous restart-compatible behavior.  `fluid` is intended
for visualization and diagnostics with large inactive pools.

## CUDA-resident fast path

When the shared CUDA particle state is fresh and the filter is `fluid`, 0314:

1. downloads only the full `role[]` byte array;
2. builds compact contiguous runs of `role=Fluid` particles;
3. downloads `x/y/vx/vy/mass/type` only for selected ranges;
4. writes a normal V2 `.smpcd` file containing only fluid particles.

This avoids transferring and writing the huge inactive tail.  It also avoids the
host summary loop over inactive slots when `summaryRoleFilter=fluid`.

## Caution

A `dumpRoleFilter=fluid` dump is **not** a full restart image with the original
inactive capacity.  Use it for visualization/post-processing.  Use
`dumpRoleFilter=all` when the dump must preserve the reservoir for restart.

## Visual scripts

The 0309 visual scripts now default to:

```bash
DUMP_ROLE_FILTER=fluid
SUMMARY_ROLE_FILTER=fluid
```

Override explicitly for restart-compatible dumps:

```bash
DUMP_ROLE_FILTER=all SUMMARY_ROLE_FILTER=all bash scripts/run_demo_visual_von_karman_resampling_0309.sh
```
