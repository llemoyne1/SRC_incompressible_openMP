# Algorithmic validation campaign 0435e

## Scope

This campaign checks executable access and backend plumbing. It does not claim
physical equivalence between SRC, resampling and Q6 formulations.

Eight autonomous 0434 cases were run on all four integrated paths:

- Taylor-Green periodic;
- Poiseuille periodic-x / solid-y;
- backward-step Darcy with segmented left/right IO;
- same-face segmented IO box;
- type-1 injection into type-2 with segmented left/right IO;
- bend-pipe Darcy with segmented IO;
- periodic-x NACA Darcy;
- periodic-x von Karman Darcy.

Paths: `src`, `src-resampling`, `src-q6`, `src-q6-resampling`.

The adapted grids range from 48x48 to 72x24. Every simulation runs 300 steps
with summaries every 50 steps. This exercises 60 population-guard periods at
the retained cadence of five steps. Live visualization and filtered recording
are disabled to isolate solver execution.

All Darcy cases use the retained reduced validation model:

- `darcyBrinkmanForcingMode=mean_outward_bath`;
- `darcyChiCollisionVpEnable=true`;
- `darcyChiCollisionVpMode=interface_band`;
- VP strength 0.25 and VP gamma equal to the run gamma.

## Outcome

Final result: **32/32 PASS at step 300**.

For every combination:

- process exit code is zero;
- runtime summary reaches step 300;
- total mass, kBT estimate and maximum particle speed are finite;
- no `fatal error`, stale shared state, unsupported path, explicit CPU fallback
  or non-finite marker is present in the captured logs;
- Q6 paths export `MPCD_CUDA_Q6_RESIDENT_0400=1`;
- resampling paths export mass recondition 0296, population guard 0297 and
  empty-refill 0319 as enabled.

The complete machine-readable result is:

- `runs/0435e_algorithmic_matrix/algorithmic_audit.csv`
- `runs/0435e_algorithmic_matrix/algorithmic_report.md`

## Remediation performed

The first pass produced 24/32 successes. All eight failures were reservoir-pool
exhaustion:

- four backward-step paths failed around steps 48-56 with only 512 inactive
  slots;
- four injection paths failed around steps 75-164 with only 1024 inactive
  slots.

This was a campaign-capacity error, not a CUDA capability restriction. The
hard reservoir correctly refuses to append beyond allocated storage. The final
campaign reserves eight domain-cell equivalents for those two net-injection
cases. No solver change was needed. The second pass completed 32/32.

## Scientific observations for the next campaign

The following are not execution blockers, but they require physical validation:

- same-face IO: global kBT is about 1.05 for SRC but 0.075 for Q6;
- von Karman: global kBT is about 4.97 for SRC but 0.022-0.023 for Q6;
- bend-pipe: global kBT is about 0.46 for SRC and 1.77-2.05 for Q6;
- backward-step Q6 is cooler than SRC;
- injection Q6 is hotter and retains a different particle population;
- resampling changes particle populations in several cases, as expected from
  the selected population-control model, but conservation and ensemble effects
  still need quantified acceptance bounds.

These differences mean that 32/32 algorithmic success must not be interpreted
as physical equivalence.

## Reproduction

```bash
BIN=build/src_mpcd_base_cuda_q6_resident_0400_livevis_0435d \
CAMPAIGN_ROOT=runs/0435e_algorithmic_matrix \
STEPS=300 SUMMARY_EVERY=50 \
bash scripts/run_0435e_algorithmic_matrix.sh
```

The launcher continues after individual failures and the summarizer emits one
row per case/path combination.
