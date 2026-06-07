# Patch 0290 — remove unused segmented-inlet host helper warning

This patch removes the obsolete host helper
`inlet_segment_index_for_cell_host_0269` from
`src/cuda_classic_src_io_resident_0263.cu`.

Since patch 0288, host-side segmented-reservoir counting uses the interval-aware
helper `inlet_segment_index_for_cell_interval_host_0288`, which clips partially
open inlet cells at segment endpoints. The older point/center-based host helper
was no longer referenced and produced the nvcc warning:

```text
warning #177-D: function "mpcd::<unnamed>::inlet_segment_index_for_cell_host_0269" was declared but never referenced
```

No runtime path is changed. Device-side point-based helpers are kept because
other non-reservoir segmented boundary checks still use them.

Recommended check:

```bash
bash scripts/build_src_mpcd_cuda_0288.sh
```

or the latest consolidated build script available in the working tree.
