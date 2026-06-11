# GPU patch 0320 — VK wall resident fast diagnostics defaults

This patch is script-only. It does not modify the C++/CUDA solver and does not
require recompilation.

## Measured motivation

On the 192x64 VK-like periodic/wall/circle benchmark after 0318b+0319, the
0320 probe with existing runtime flags showed:

- total elapsed: about 20.39 s -> about 17.45 s / 10000 steps,
- `force_stream`: about 4.00 s -> about 0.50 s,
- `wall_simple_0246` total: about 3.86 s -> about 0.335 s,
- `wall_simple_0246` download: about 2.30 s -> about 0.0004 s.

The dominant remaining cost is therefore the persistent SRC collision block,
not the wall streaming/boundary path.

## Runtime flags set by the demo runner

The Von Karman CUDA demo now defaults to:

```bash
MPCD_CUDA_CLASSIC_SRC_RESIDENT_0271_ASYNC_STREAM=1
MPCD_CUDA_CLASSIC_SRC_WALL_RESIDENT_0271_FAST_DIAGNOSTICS=1
```

The old behavior can be restored without editing the script:

```bash
SRC_GPU_ASYNC_STREAM_0320=0 SRC_GPU_WALL_FAST_DIAG_0320=0 \
  bash scripts/run_demo_src_classic_cuda_von_karman_cylinder_0285.sh
```

## Expected log line

```text
[0320-demo] WALL_FAST_DIAG_0320=1 ASYNC_STREAM_0320=1
```

## Expected verification

In `cuda_resident_phase_profile_0266.csv`, `wall_simple_0246` should remain
applied, with a strongly reduced `download_s` compared to the pre-0320 probe.
