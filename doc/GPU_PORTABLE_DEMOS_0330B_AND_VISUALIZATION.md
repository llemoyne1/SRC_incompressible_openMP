# GPU portable demo scripts updated to 0330b checkpoint

## Scope

This archive updates the five portable demo scripts supplied in the chat:

- `run_portable_tg_hole_resampling_0315.sh`
- `run_portable_poiseuille_resampling_0315.sh`
- `run_portable_box_segmented_x0_resampling_0315.sh`
- `run_portable_backward_step_resampling_0315.sh`
- `run_portable_von_karman_resampling_0315.sh`

The file names are kept for compatibility with existing documentation and habits, but the scripts now advertise the validated 0330b CUDA checkpoint in their runtime output.

## Validated checkpoint reflected in the scripts

The current retained optimization stack is:

- 0318b: wall/circle resident CUDA path for the periodic VK wall/circle case.
- 0319: skip wall virtual-particle diagnostic reconstruction in the benchmark fast path.
- 0320: wall resident fast diagnostics and async stream flags.
- 0321: fast collision/thermostat diagnostics.
- 0322: device rotation / lazy kernel check / skip setup sync.
- 0327b: resize-only host `cellId` array, avoiding the previous `assign(n,-1)` fill.
- 0330b: immersed-circle fast diagnostics, suppressing the per-step hits counter copy.

Rejected and explicitly disabled:

- 0325: wall/finalize/rotation fusion, measured as a regression.
- 0329: rotation-table cache, measured as a regression.

## Changes made to the scripts

Each script now:

1. Uses `build/src_mpcd_base_cuda_0330b` as default binary name.
2. Keeps `DUMP_ROLE_FILTER=fluid` and `SUMMARY_ROLE_FILTER=fluid` defaults, so dumps remain active-particle/fluid-oriented rather than inactive-slot dumps.
3. Adds `portable_cuda_classic_fast_flags_0330b`, which enables the validated fast-path flags.
4. Logs `SRC_GPU_*` options in each `environment_0315.env`.
5. Keeps rejected experiments 0325 and 0329 disabled by default.
6. Keeps the existing MATLAB `play_smpcd_dumps` helpers.

## Important caveat

These are updated demo runners. They do not modify the solver. They assume the solver source has already incorporated the validated 0318b/0319/0320/0321/0322/0327b/0330b code paths.

## Suggested quick smoke

```bash
cd /mnt/e/SRC_MPCD_dev/SRC_GPU
unzip -o gpu_portable_demos_0330b_files_only.zip -d .

# Short smoke on Poiseuille
STEPS=200 DUMP_STATE_EVERY=100 RUN_MODES=classic \
  bash scripts/run_portable_poiseuille_resampling_0315.sh

# Short smoke on periodic VK
VK_MODE=periodic NX=192 NY=64 GAMMA=20 STEPS=500 DUMP_STATE_EVERY=100 RUN_MODES=classic \
  bash scripts/run_portable_von_karman_resampling_0315.sh
```

Expected terminal markers include:

```text
[0330b-portable] checkpoint: 0318b+0319+0320+0321+0322+0327b+0330b; 0325/0329 disabled
```

For VK periodic, also expect the 0318b/0330b relevant environment flags in `logs/environment_0315.env`.

## Visualization feasibility: porting the `mpcd_vkkh_play.cu` live view

`mpcd_vkkh_play.cu` contains a useful real-time visualization architecture:

- build a coarse Eulerian visualization grid directly on GPU from particle arrays;
- accumulate local velocity/mass/tracer quantities;
- smooth the coarse field;
- compute scalar fields such as vorticity, speed, `Ux`, `Uy`, tracer;
- color-map to an RGBA buffer;
- render with GLFW/OpenGL;
- use CUDA/OpenGL interop when available;
- fall back to CUDA-to-CPU RGBA upload when interop is unavailable, which is useful under WSLg.

This is implementable in `src_cuda_v2`, but should be a separate optional module, not part of the physical step.

### Recommended implementation plan

1. Add an optional module:
   - `src/cuda_realtime_vis_0331.cu`
   - `src/cuda_realtime_vis_0331.h`

2. Gate at build time and runtime:
   - build-time: `USE_GL_VIS` or `MPCD_ENABLE_GL_VIS`
   - runtime `.kv`: `visualizationEnable`, `visualizationStride`, `visualizationField`, `visualizationNx`, `visualizationNy`, `visualizationSmoothPasses`, `visualizationClip`, `visualizationAlpha`.

3. Hook after the CUDA-resident particle state is updated, not before:
   - use `state.NactiveFluid`, not `state.Np`;
   - filter `role == Fluid`;
   - ignore inactive slots;
   - avoid modifying physical arrays.

4. Use mass-aware accumulation for SRC:
   - `sumMass`, `sumMassUx`, `sumMassUy`;
   - `Ux = sumMassUx / sumMass`;
   - `Uy = sumMassUy / sumMass`;
   - density field from `sumMass / cellArea`.

5. Support obstacle overlays:
   - periodic/walls;
   - rectangle;
   - circle;
   - optional mask from immersed-solid geometry.

6. Avoid physical-step synchronization:
   - update only every `visualizationStride`;
   - use a separate CUDA stream where practical;
   - keep it disabled by default.

### Risks

- Requires GLFW/OpenGL build dependencies.
- CUDA/OpenGL interop may be unavailable under WSL; the fallback CPU upload path is necessary.
- The SRC code uses `double` arrays and roles/masses, whereas `mpcd_vkkh_play.cu` uses a leaner `float` layout. The visualization kernels should therefore be written for the SRC data model rather than pasted as-is.
- The live visualization must never force full dumps or inactive-slot downloads.
- The first implementation should be display-only. It should not become a required dependency for headless runs.

### Recommendation

Implement the live visualization later as patch 0331, not in the demo-script refresh. The clean starting point is a display-only module that mirrors the VKKH visualization pipeline but reads the SRC persistent particle arrays with `NactiveFluid` and role filtering.
