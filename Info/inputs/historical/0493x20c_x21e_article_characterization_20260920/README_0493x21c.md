# 0493x21c — capillary shadow Young–Laplace

Purpose: validate the resolved Laplace mechanism without ever treating a free `sigma=0` drop as a stationary reference.

Default point: x13h fluid (`gamma=8`, rotation `120 deg`, `lambda/h=0.72`, `kBT=0.125`), `256x256`, `R/h=64`, `sigma=945`, `Rmin/h=4`.

Protocol:
1. one active `sigma=945` circular drop, 1000 steps, state dump every 100;
2. automatic geometry-plateau detection from active x9e diagnostics;
3. three state checkpoints selected within the plateau;
4. at each checkpoint, six RNG replicates of twin 2-step restarts from the *same state*: one at `sigma=945`, one at `sigma=0`;
5. primary Young–Laplace increment uses the first positive-step x9e diagnostic row only.

The `sigma=0` shadow is therefore a differential control, not a physical stationary drop.

Commands:
```bash
bash scripts/run_0493x21c_capillary_shadow_young_laplace.sh --preflight
LIVE_PROGRESS=1 bash scripts/run_0493x21c_capillary_shadow_young_laplace.sh --run
```

Staged execution is also available:
```bash
bash scripts/run_0493x21c_capillary_shadow_young_laplace.sh --active
bash scripts/run_0493x21c_capillary_shadow_young_laplace.sh --shadows
```

Decisive outputs:
- `analysis/capillary_shadow_decision_0493x21c.txt`
- `analysis/shadow_pair_realizations_0493x21c.csv`
- `analysis/shadow_checkpoint_summary_0493x21c.csv`
- `analysis/selected_checkpoints_0493x21c.csv`
- `audit/traceability_0493x21c.txt`


## fix1 — effective dump cadence

The common 0434 parameter writer is authoritative for `summaryEvery` and
`dumpStateEvery`.  fix1 synchronizes `DUMP_STATE_EVERY` with the requested
per-run cadence before invoking the helper and adds a post-run guard on the
number of `state_step_*.smpcd` files.  This fixes the case where the active
trajectory was physically valid but only the final step was dumped.

No physics parameter is changed: the default remains `sigma=945`, `R/h=64`.
