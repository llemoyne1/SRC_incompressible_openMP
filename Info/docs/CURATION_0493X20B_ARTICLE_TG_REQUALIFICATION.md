# 0493x20b — Long Taylor–Green requalification for the JCP fluid campaign

Purpose: replace the short-pilot TG metrology of x20a by a statistically stronger, domain-enlarged viscosity campaign without replaying the already clean MSD and SRC acoustics.

The x20a pilot used a 64x64 TG domain, T=4 and three seeds. At least one of SRC/Q6-G-F was REVIEW, INVALID or missing at every physical point, so using only a subset of replays would make the final SRC/Q6-G-F ratios heterogeneous. x20b therefore replays TG on all 12 x20a physical points and both numerical paths.

Metrology changes only; no solver physics changes:
- TG grid 128x128 (L=0.5 for h=1/256), increasing the modal decay time scale by a factor four relative to x20a and improving spatial modal averaging;
- six common seeds per case/model: the original three x20a TG seeds plus three new deterministic independent seeds;
- physical duration selected per case from the x20a pilot viscosity so that the slower path is observed for approximately three decay times, with explicit margin;
- dump count `max(48, ceil(T/0.4))` to retain adequate temporal sampling while bounding raw-state volume;
- `CALIBRATION_EXPERIMENTS=tg` only; no MSD or sound rerun;
- gamma=4 SRC is therefore measurable because the x20a failure came from the separate sound-state initializer, not TG.

Durations: L036=16, L048=18, L060=20, L072=20, L090=18; gamma 4/6/12/16 = 12/20/22/20; alpha 60/90/150 = 32/36/10.

The campaign comprises 12 cases x 2 models x 6 seeds = 144 solver TG realizations. The runner retains campaign-level restart through the standalone calibrator `.complete` markers and `SKIP_EXISTING=1`.

Outputs:
- `tg_results_aggregated.csv`: model-level viscosity, standard deviation, CV, individual fit counts and R2 summaries;
- `tg_realizations.csv`: seed-level viscosity and TG fit diagnostics;
- `tg_ratios_paired.csv`: status-aware ratio of means plus seed-paired Q6-G-F/SRC ratios and their uncertainty;
- `tg_vs_x20a_pilot.csv`: optional comparison with the short x20a pilot when the pilot summary remains in its default run directory.

Invalid model ensembles are never published as article ratios by the x20b aggregation logic.
