# 0493x22h — grid phase-profile decomposition at constant gamma

Purpose: explain the nearly grid-independent ~3x Q6-G-F/SRC wall-time ratio observed in x22g.

This diagnostic reuses the exact x22g production-path parameter generation and flags, but enables `MPCD_INTERNAL_PROFILES=1`, uses one measured run per variant and grid, and shortens the run because the objective is phase decomposition, not publication timing statistics.

Defaults: gamma=20, N=64 96 128 192 256, h=1/256, same dt/kBT/periodic BCs/x7j path as x22g, 50-step warmup and 400 measured steps.

Outputs:
- `analysis/grid_phase_profile_summary.txt`
- `analysis/grid_phase_profile.csv`
- `analysis/grid_q6_profile.csv`

No solver source or physics is modified.
