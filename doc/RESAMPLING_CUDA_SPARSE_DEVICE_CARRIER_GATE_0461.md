# 0461A sparse device-carrier gate probe

This patch keeps the 0460B Thrust cell-list materializer and CUDA mutation path active at every step, while making the expensive strict device-carrier operation-buffer gate sparse.

Environment flags:

- `MPCD_CUDA_RESAMPLING_SPARSE_DEVICE_CARRIER_GATE_0461=1` enables sparse full-gate mode.
- `MPCD_CUDA_RESAMPLING_DEVICE_CARRIER_GATE_EVERY_0461=N` performs the full gate on the first device-carrier call and every N calls thereafter.

Non-full-gate pass rows are omitted from `cuda_resampling_device_carrier_0455.csv`; failures still emit rows. The small `outCount`/`invalidOps` checks and CUDA apply path remain active every step.
