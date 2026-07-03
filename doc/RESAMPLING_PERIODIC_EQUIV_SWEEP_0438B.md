# 0438B periodic path-equivalence sweep

This step extends the 0438 wall-free validation matrix with seed/gamma sweeps.
It does not introduce a solver parameter and does not modify solver semantics.

The physical comparisons remain pairwise only:

- `src-resampling` versus `src`
- `src-q6-resampling` versus `src-q6`

The goal is to distinguish one-realization stochastic scatter from systematic
resampling bias in periodic, wall-free configurations.  Wall, solid, chi/Darcy,
inlet/outlet and injection cases remain excluded from equivalence claims.

Recommended first campaign:

```bash
BIN=build/src_mpcd_base_cuda_q6_resident_periodic_equiv_0438 \
CASE=shear \
BASE_SWEEP_ROOT=runs/0438b_shear_periodic_equiv_g40_s2000_3seeds \
GAMMAS="40" STEPS_LIST="2000" \
SEEDS="1628638 1628639 1628640" \
RUN_MODES="src src-resampling src-q6 src-q6-resampling" \
SUMMARY_EVERY=100 LIVE_VIS_ENABLE=0 FILTERED_RECORDING_ENABLE=0 \
bash scripts/run_0438b_periodic_equiv_sweep.sh
```

The aggregate outputs are:

- `periodic_equiv_sweep_summary_0438b.csv`
- `periodic_equiv_sweep_report_0438b.md`
