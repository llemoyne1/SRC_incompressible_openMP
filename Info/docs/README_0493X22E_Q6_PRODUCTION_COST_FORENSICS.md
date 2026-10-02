# 0493x22e — Q6 production-profile cost forensics

Diagnostic only. No source modification, no rebuild and no physics change.

This corrects two ambiguities in x22d:

1. historical `src-q6` production explicitly sets `MPCD_CUDA_Q6_RESIDENT_SINGLE_BLOCK_CG_0407=1` when `Nx*Ny <= 65536`;
2. current `src-q6-g-f` production explicitly sets `MPCD_Q6_G_F_RESIDENT_CG_0493X7J=1` and `MPCD_CUDA_Q6_RESIDENT_SINGLE_BLOCK_CG_0407=0`.

The script uses those exact policies, not an unset/"AUTO" environment state.

It profiles three variants (`SRC_PROD`, `Q6_PROD_0407`, `Q6GF_PROD_X7J`) on two grids with identical spatial step `h=1/256`:

- G128: 128x128 over 0.5x0.5, matching the article transport calibration grid family;
- G256: 256x256 over 1x1, matching the earlier x22 diagnostic scale.

Common microscopic point: gamma=8, alpha=120 deg, dt=0.0063471328149122585, kBT=0.125, m=1, seed=4933301, projection tolerance 1e-5, max iterations 800.

Built-in internal profiling (`MPCD_INTERNAL_PROFILES=1`) reports wall time and Q6 deposit/solve/apply components. The output is diagnostic; performance claims for the paper remain frozen until this scaling check is interpreted.
