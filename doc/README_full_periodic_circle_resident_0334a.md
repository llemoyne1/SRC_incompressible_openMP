# 0334a — general resident SRC classic path for periodic + CUDA immersed circle

This patch targets the benchmark gap observed in `vk_mono_vs_src_0333`: `immersed_circle_0284` was doing one upload and one download per step and `periodic_0245` was requested but unsupported when `immersedSolidEnable=true`.

Changes:

- `cuda_streaming_periodic_0245.cu`
  - Allows periodic streaming even when an immersed solid is enabled. Streaming is independent of the immersed-solid shape; if the downstream CUDA immersed handler refuses the case, `src_mpcd_base.cpp` synchronizes before CPU fallback.

- `cuda_immersed_circle_0284.cu`
  - Treats the circle handler as resident for classic CUDA periodic, wall, solid-rectangle, and IO resident families. This keeps the circle reflection on the shared `CudaParticleState` instead of forcing upload/download per step.

- `src_mpcd_base.cpp`
  - Allows the periodic resident family when the immersed solid is handled by a CUDA immersed handler.
  - Skips the CPU boundary pass after resident periodic streaming, because 0245 already applies full periodic wrapping.
  - Adds a boundary-family-neutral active-prefix synchronization helper for CPU fallback consumers, not only IO.
  - Removes the unconditional active-prefix download before CUDA immersed handlers; the download is now only performed before CPU fallback.

Validation target:

- `periodic_0245` should become `supported=1, handled=1` in `cuda_resident_phase_profile_0266.csv`.
- `immersed_circle_0284` should show `uploadCalls=0`, `downloadCalls=0` after the initial resident upload, except for summary/final lazy synchronization.
- `SRC_CLASSIC_NINACT0` in the 0333 benchmark should drop substantially from ~3.4 ms/step.

This patch deliberately does not re-enable the unsafe wall+circle 0318 shortcut.
