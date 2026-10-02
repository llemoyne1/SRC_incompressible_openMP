# 0493x22b-fix1 path diagnostic

Purpose: invalidate/diagnose the original x22b cost ratio before publication.

The original x22b A1 was not a plain liquid projection. It enabled the Q6-G-F free-surface architecture (`free_surface_masked`, x6c/x6e/x6f geometry/topology/stencil, x6h-B1 RT0, species registry and prestream fused projection). Therefore its ~3.7x ratio must not be interpreted as the cost of liquid projection.

This diagnostic compares on the exact same state and binary:

- A0_SRC: historical SRC path;
- A1_SRC_Q6: historical plain `src-q6` path, with no species registry and all Q6-G-F free-surface gates OFF;
- A2_OLD_X22B_Q6GF: reproduces the old invalid x22b A1 architecture for attribution only.

Two balanced 500-step repetitions are diagnostic only. If A1 is well behaved, a separate 5-pair publication benchmark should then be run with A0/A1 only.
