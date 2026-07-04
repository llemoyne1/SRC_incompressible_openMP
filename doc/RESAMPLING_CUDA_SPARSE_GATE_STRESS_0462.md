# 0462 — Sparse gate stress validation

This validation runner exercises the 0461 sparse device-carrier gate over multiple seeds, using the 0460 Thrust stable cell-list materializer. It does not introduce a new solver path; it verifies that sparse full-gating remains safe over repeated periodic nonzero-plan runs.

Default scope:

- seeds: `1628638 1628639 1628640`
- steps: `200`
- modes: `src-resampling src-q6-resampling`
- full gate cadence: `DEVICE_GATE_EVERY=50`
- progress display enabled by default through `LIVE_PROGRESS=1`

Expected behavior:

- CPU/CUDA summary deltas remain at roundoff level.
- Full gate rows are sparse, typically steps `1, 50, 100, 150, 200` for 200-step runs.
- Operation counts and strict gate diagnostics match on every gated row.
- Device-carrier CSV volume is reduced relative to full per-step gating.

This is a stress/validation step for 0461, not a new materializer.
