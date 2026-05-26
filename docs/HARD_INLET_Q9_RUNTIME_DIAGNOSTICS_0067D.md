# 0067d — Q9 safety runtime diagnostics for hard-inlet backward-step runs

This patch makes the Q9 safety counters visible in `summary_runtime.csv` and therefore in
`summary_hard_inlet_validation_0067.csv`.

It does not change the numerical method.  It only exports diagnostics that were already
computed in `Q9ProjectionDiagnostics`:

- `q9SafetyActiveCells`
- `q9SafetyExcludedCells`
- `q9OpenBoundaryExcludedCells`
- `q9ImmersedHaloExcludedCells`
- `q9LowMassSuppressedCells`
- `q9VelocityLimitedCells`
- `q9CorrectionVelocityRawRms`
- `q9CorrectionVelocityRawMaxAbs`
- `q9CorrectionVelocityLimiter`
- `q9MinCellMassForCorrection`

The hard-inlet analysis also reports derived quantities:

- `q9VelocityLimitedFractionFinal`
- `q9RawOverLimiterFinal`
- `q9RmsOverLimiterFinal`

These are intended to distinguish a safe, lightly limited Q9 correction from a case where
the limiter is constantly saving an overly aggressive correction.

Recommended rerun after applying this patch:

```bash
./scripts/build_src_mpcd_base.sh
CASE_STEPS=1000 ./scripts/run_backward_step_hard_inlet_validation_0067.sh
```

Then:

```matlab
cd matlab
S = analyze_backward_step_hard_inlet_validation_0067('root','..');
cd ..
```

Expected hard-inlet diagnostics:

- `inletReservoirStdNFinal = 0`
- `inletReservoirMinNFinal = inletReservoirMaxNFinal = 20`
- `inletMeanUxFinal ≈ 0.05`
- `inletKBTFinal ≈ 0.0025`

Expected Q9 diagnostics for soft runs:

- `q9CorrectionVelocityMaxAbsFinal ≈ q9CorrectionVelocityLimiterFinal = 0.003`
- `q9VelocityLimitedFractionFinal` finite, not `NaN`
- `q9RawOverLimiterFinal` finite, not `NaN`
- `q9RmsOverLimiterFinal` finite, not `NaN`

For validation, prefer cases where the Q9 temperature is close to the Q6 reference and the
limited-cell fraction remains modest.  If the raw correction greatly exceeds the limiter
or too many active cells are limited, reduce `q9MassFluxProjectionStrength` or enlarge the
Q9 exclusion/halo zones before interpreting the result physically.
