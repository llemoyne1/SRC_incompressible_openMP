# 0336b — keep resampling live visualization safe by default

The experimental 0336a snapshot can return a compact array but lose most physical content after a few resampling edits.  This means the shared 0251 particle arrays are not always authoritative after CUDA resampling invalidates the fresh marker.

0336b therefore:

- adds a conservative sanity check before accepting a CUDA snapshot for live visualization;
- defaults `MODE=resampling` back to the known-good host-mirror visualization path;
- keeps the experimental snapshot available only on explicit request.

Known-good resampling visualization:

```bash
SRC_LIVE_VIS_CUDA_SNAPSHOT=0
SRC_LIVE_VIS_RESAMPLING_HOST_MIRROR=1
```

Experimental snapshot test:

```bash
SRC_LIVE_VIS_CUDA_SNAPSHOT=1
SRC_LIVE_VIS_RESAMPLING_HOST_MIRROR=0
SRC_LIVE_VIS_LOG_SOURCE=1
```

If the snapshot is rejected, logs include:

```text
source=cuda_snapshot_rejected_host_fallback_0336
```
