# 0452 — CUDA resampling upstream apply-gate stress

0452 is a validation-only step. It does not modify the solver.

It stresses the 0451 upstream apply-gate on periodic, wall-free, no-chi, no-Darcy, no-inlet/outlet nonzero-plan cases. CUDA recomputes the upstream resampling stages in the real solver:

- deposit / cell moments,
- poor/rich classification,
- receiver/donor compaction,
- transfer planner.

The upstream CUDA result is accepted only through the strict 0451 CPU/GPU equivalence gate. The 0448 CUDA apply backend remains authoritative for the clean mutating stages:

- passive extraction / insertion,
- remap mass/momentum,
- thermal renormalization.

The host workspace is still present as a mirror for legacy donor-particle operation materialization. Therefore, 0452 is not yet the final host-free resampling backend.

## Runner

```bash
BIN=build/src_mpcd_base_cuda_q6_resident_periodic_equiv_0451 \
BASE_STRESS_ROOT=runs/0452_upstream_apply_gate_stress \
STEPS_LIST="20 100" \
SEEDS="1628638 1628639 1628640" \
RUN_MODES="src-resampling src-q6-resampling" \
SUMMARY_EVERY=1 \
LIVE_VIS_ENABLE=0 \
FILTERED_RECORDING_ENABLE=0 \
bash scripts/run_0452_upstream_apply_gate_stress.sh
```

The runner calls `scripts/run_0451_upstream_apply_backend_smoke.sh` for each `(steps, seed)` pair, then aggregates all `upstream_apply_summary_0451.csv` files into:

- `upstream_apply_stress_summary_0452.csv`
- `upstream_apply_stress_report_0452.md`

## Expected pass criteria

- `PASS-like rows = all rows`,
- `maxSummaryDelta <= 1e-9`,
- CPU/GPU transfer-pair counts match,
- `cellIdMismatch = 0`,
- `countDiff = 0`,
- receiver/donor list mismatch is zero,
- `planMismatch = 0`,
- `maxMassAbs = 0`,
- `maxPlanMassAbs = 0`,
- `maxPlannedMassDelta = 0`.

A PASS 0452 validates the gated upstream CUDA authority plus 0448 CUDA apply backend over multiple seeds and time horizons.
