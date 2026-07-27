# 0493o0 — SRC-only dual-bench baselines

This additive qualification patch introduces no solver modification and requires no rebuild.
It adds two instrumented SRC-only runners for the future asymmetric resampling development:

- `scripts/run_0493o0_src_baseline_tg.sh`: periodic Taylor–Green physical-fidelity bench;
- `scripts/run_0493o0_src_baseline_segmented_darcy.sh`: segmented inlet/outlet, external walls and file-driven Darcy/chi obstacle general-capability bench.

Both runners:

- force `MODE=src`;
- disable Q6 and every mutating resampling brick;
- retain passive support survey 0295, adaptive/geometry/outlier diagnostics 0304–0306, internal profiles, summaries, state dumps and filtered-field recording;
- default to `LIVE_PROGRESS=1` and LiveVis enabled;
- hard-wire `SRC_LIVE_VIS_CONTROL_FILE` to `<repository-root>/livevis_control.kv`;
- never create or use a run-local `livevis_control.kv`.

The root control file is created only when absent. Existing user controls are preserved unless `OVERWRITE_LIVEVIS_CONTROL=1` is explicitly supplied.

## Preflight

```bash
PREFLIGHT_ONLY=1 LIVE_PROGRESS=1 bash scripts/run_0493o0_src_baseline_tg.sh
```

then

```bash
PREFLIGHT_ONLY=1 LIVE_PROGRESS=1 bash scripts/run_0493o0_src_baseline_segmented_darcy.sh
```

## Runs

```bash
LIVE_PROGRESS=1 bash scripts/run_0493o0_src_baseline_tg.sh
```

```bash
LIVE_PROGRESS=1 bash scripts/run_0493o0_src_baseline_segmented_darcy.sh
```

The two runners intentionally share the same repository-root livevis control file. The generated states, chi field, params, logs, dumps, recordings and output CSVs remain isolated under `runs/0493o0_src_baseline_dual_bench/`.
