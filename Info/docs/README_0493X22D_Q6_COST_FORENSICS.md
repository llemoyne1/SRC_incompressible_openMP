# 0493x22d — Q6 cost forensics

Diagnostic-only article support. No source/physics modification and no rebuild.

Purpose: explain the anomalous x22b/x22b-fix1 timing ratios by profiling the current CUDA-resident paths. The x22b-fix1 diagnostic accidentally forced `MPCD_CUDA_Q6_RESIDENT_SINGLE_BLOCK_CG_0407=0` on the plain Q6 case although the 256x256 grid has exactly 65536 cells, the default 0407 eligibility threshold.

Five short 400-step runs use the same nominal bulk state:

- SRC
- Q6_AUTO0407: historical common Q6 with normal 0407 automatic selection
- Q6_OFF0407: same common Q6 with 0407 forced off (reproduces the slow-path choice)
- Q6GF_AUTO0407: Q6-G-F, x7j resident CG, normal 0407 automatic selection
- Q6GF_OFF0407: Q6-G-F, x7j resident CG, 0407 forced off (configuration used by some later campaign runners)

`MPCD_INTERNAL_PROFILES=1` writes `phase_profile_0163.csv` and `q6_cg_profile_0163.csv`. Q6-G-F also supplies x7j audit fields. These measurements are diagnostic; do not use any cost ratio in the paper before interpreting the internal decomposition.
