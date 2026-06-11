# 0318b — script-only activation fix for wall+circle resident path

The 0318 binary can contain `MPCD_CUDA_CLASSIC_SRC_WALL_CIRCLE_RESIDENT_0318`, but the runtime path can still remain inactive if the demo runner clears CUDA flags via `src_gpu_cuda_env_clear_0283` and does not set `MPCD_CUDA_STREAMING_WALL_SIMPLE_0246=1` afterwards.

This script-only update forces the three runtime flags immediately after the clear helper in `scripts/run_demo_src_classic_cuda_von_karman_cylinder_0285.sh`:

- `MPCD_CUDA_CLASSIC_SRC_WALL_CIRCLE_RESIDENT_0318=1`
- `MPCD_CUDA_STREAMING_WALL_SIMPLE_0246=1`
- `MPCD_CUDA_STREAMING_WALL_SIMPLE_0246_DOWNLOAD_ALL=0`

It also prints a single `[0318b-demo]` line in stdout so the run log proves that the intended runtime flags were active. No solver file is modified and no rebuild is required.

Expected validation signal in `cuda_resident_phase_profile_0266.csv`:

- a `wall_simple_0246,force_stream,...` row should appear;
- `immersed_circle_0284` upload time/calls should drop strongly relative to the 0318 inactive profile (`uploadCalls≈9984`, `upload_s≈25 s`).
