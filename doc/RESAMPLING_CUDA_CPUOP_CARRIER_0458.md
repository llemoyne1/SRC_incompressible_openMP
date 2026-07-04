# 0458A CPU-op carrier performance bridge

This is a diagnostic bridge, not the final host-free materializer.

The validated 0453/0455 CUDA donor-particle materializer is currently implemented by
`materialize_passive_ops_serial_kernel_0453<<<1,1>>>`, which is correct but serial and
therefore much too slow for performance tests.

0458A adds `MPCD_CUDA_RESAMPLING_CPU_OP_CARRIER_0458=1`. When enabled inside the 0455
device-carrier path, the already accepted CPU passive operation vector is copied into
the device-carrier buffers and consumed by the CUDA extraction/insertion backend. This
bypasses the serial CUDA materializer while preserving the same downstream CUDA apply,
remap, and thermal path.

Purpose:

- isolate the serial materializer cost;
- determine whether the remaining CUDA apply/remap/thermal path is viable;
- avoid claiming a host-free donor-particle materializer before implementing one.

Expected outcome:

- `cpuOpCarrier0458=1` in `cuda_resampling_device_carrier_0455.csv`;
- `materializeKernelSeconds=0` for the CPU-op carrier branch;
- CPU baseline vs CUDA CPU-op carrier summary deltas at roundoff;
- invalid materialize/apply operations equal zero.

Next step after this diagnostic: implement a true parallel CUDA donor-particle
materializer to replace `materialize_passive_ops_serial_kernel_0453<<<1,1>>>`.
