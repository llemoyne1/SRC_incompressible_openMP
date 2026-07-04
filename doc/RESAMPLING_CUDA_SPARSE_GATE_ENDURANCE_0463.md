# 0463 — Sparse-gate endurance validation

This validation extends the 0462 sparse-gate stress runner to a longer periodic nonzero-plan endurance run.

Reference configuration:

- Seed: `1628638`
- Steps: `1000`
- Summary period: `100`
- Device full-gate period: `100`
- Modes: `src-resampling`, `src-q6-resampling`
- CUDA path: 0460 Thrust stable cell-list materializer + 0461 sparse device-carrier gate

Validated result:

- PASS-like rows: 2/2
- CSV/full-gate rows: 11 per mode
- CPU/GPU operation counts: 556/556
- Invalid materialize/apply ops: 0/0
- Operation/duplicate mismatches: 0/0
- Max final summary delta: order 1e-13 to 1e-12

This confirms that sparse operation-buffer gates do not mask a slow drift over 1000 steps in the periodic nonzero-plan validation case.
