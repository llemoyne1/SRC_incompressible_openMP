# 0306 runner fix: diagnostic-only success

The 0306 outlier diagnostics only require `output/cuda_resampling_adaptive_flag_0304.csv` and optional state dumps. Some legacy 0283 demo wrappers return a non-zero code when `summary_runtime.csv` is missing after a successful binary run.

This fix makes `scripts/run_cuda_resampling_outlier_diagnostics_0306.sh` accept such runs when:

- the wrapper returned non-zero,
- `ALLOW_DIAG_ONLY_SUCCESS` is enabled,
- `output/cuda_resampling_adaptive_flag_0304.csv` exists and is non-empty,
- at least one `state_step_*.smpcd` dump exists.

The original wrapper return code is preserved in the manifest `extraEnv` field as `wrapperRc=...`.

Set `ALLOW_DIAG_ONLY_SUCCESS=0` to restore strict wrapper behavior.
