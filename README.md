# SRC_GPU-VIZ

Branch dedicated to optional real-time / interactive visualization for the CUDA resident SRC/MPCD code.

Base checkpoint:
- fastest validated SRC_GPU state: 0318b + 0319 + 0320 + 0321 + 0322 + 0327b + 0330b
- rejected experiments removed: 0325, 0329

Scope:
- keep the physical solver unchanged by default;
- add visualization as an optional display-only module;
- preserve headless runs;
- preserve autonomous demo scripts;
- never make GLFW/OpenGL mandatory for non-visual runs.

Initial demos:
- scripts/run_portable_tg_hole_resampling_0315.sh
- scripts/run_portable_poiseuille_resampling_0315.sh
- scripts/run_portable_box_segmented_x0_resampling_0315.sh
- scripts/run_portable_backward_step_resampling_0315.sh
- scripts/run_portable_von_karman_resampling_0315.sh
