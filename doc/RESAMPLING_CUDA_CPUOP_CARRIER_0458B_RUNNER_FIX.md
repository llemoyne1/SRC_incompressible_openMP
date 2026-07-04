# 0458B CPU-op carrier runner fix

0458A injected the CPU-op carrier bridge in the solver, but the performance runner nested `run_0455_device_carrier_smoke.sh` once per artificial variant. Because the 0455 report may return non-zero even when the solver sub-runs exit 0, `set -e` stopped the wrapper before aggregation.

0458B replaces the runner with a robust mode-oriented wrapper:
- call the 0455 smoke once per requested mode;
- pass `MPCD_CUDA_RESAMPLING_CPU_OP_CARRIER_0458=1`;
- preserve `LIVE_PROGRESS=1` by default;
- continue aggregation even if the nested smoke report exits non-zero;
- compare the nested CPU baseline and CUDA CPU-op summaries;
- read `cuda_resampling_device_carrier_0455.csv` and report `cpuOpCarrier0458` rows.

This remains a performance bridge, not the final host-free materializer.
