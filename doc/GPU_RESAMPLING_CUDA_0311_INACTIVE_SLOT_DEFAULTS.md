# 0311 — Direct inactive-slot default fix

This patch removes the accidental global `INACTIVE_SLOTS=5000000` assignment from
`src_gpu_resampling_demo_common_0303.sh`.  The common resampling helper must not
override per-case reservoir sizing because many CUDA kernels and dump/diagnostic
paths still scale with total particle capacity.

## Rationale

The 0310 scaling attempt showed `inactiveLogged=5000000` for all requested slot
counts.  The cause was not physics but a shell default in the common helper, which
was sourced before case scripts selected their own defaults.  This made even light
visual demos allocate millions of inactive slots.

## New behavior

- `src_gpu_resampling_demo_common_0303.sh` no longer assigns `INACTIVE_SLOTS`.
- Each case script keeps its own default, or the user may override from the shell.
- The common metadata/banner now records the effective inactive-slot value.
- The 0309 Von Karman visual default is reduced from 250000 to 120000; larger
  values remain available through `INACTIVE_SLOTS=...`.

## Suggested commands

```bash
# default visual VK, finite reservoir
BIN=build/src_mpcd_base_cuda_0308 FORCE_REBUILD=0 \
  bash scripts/run_demo_visual_von_karman_resampling_0309.sh

# increase only if the reservoir actually exhausts
INACTIVE_SLOTS=180000 BIN=build/src_mpcd_base_cuda_0308 FORCE_REBUILD=0 \
  bash scripts/run_demo_visual_von_karman_resampling_0309.sh
```

This is not the final active-list/free-list optimization.  It is a direct
low-risk fix that prevents accidental million-slot scans in current demo and
validation scripts.
