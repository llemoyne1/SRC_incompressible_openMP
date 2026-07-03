# 0438C — Resampling stage audit

This helper inspects `summary_runtime.csv` files produced by the 0438 periodic
path-equivalence runners and separates:

- resampling being computed,
- remap / thermal renormalization,
- mass guard,
- population guard,
- latent activation,
- actual nonzero transfer-pair rows.

The `transferPairRows` column counts rows where `resampTransferPairs` is nonzero.
This avoids confusing a built transfer-plan stage with an actual poor/rich
particle transfer.

Usage:

```bash
python3 scripts/analyze_resampling_stages_0438c.py --root runs/<run-root>
cat runs/<run-root>/resampling_stage_audit_0438c.md
```
