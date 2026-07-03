# Step 0434 resampling performance diagnosis

Date: 2026-07-03

## Controlled profile

Case: `run_0434_step.sh`, `960 x 480`, `gamma=7`, five steps, current
livevis-enabled binary, livevis and filtered recording disabled for timing.

Total elapsed time was 16.22 s. The internally profiled simulation time was
14.48 s, or 2.90 s/step.

| Phase | ms/step | Share |
|---|---:|---:|
| weighted-resampling initial deposit/plan | 1046 | 36.1% |
| weighted-resampling post-guard deposit/plan | 764 | 26.4% |
| CPU mass guard | 468 | 16.2% |
| thermal renormalization after remap | 131 | 4.5% |
| SRC collision | 130 | 4.5% |
| streaming | 118 | 4.1% |

The detailed deposit profile shows about 0.99 s/call in `candidate_lists`,
including about 0.97 s/call in `transfer_plan_build`. The planner repeatedly
searches the donor list for each receiver deficit. The step case exposes this
poor scaling because it has about 340,000 wet cells, 2.4 million active
particles, and tens of thousands of under-populated cells after grid shifting.

## Backend path

The resident CUDA SRC path is active. CUDA mass reconditioning 0296 and CUDA
population guard 0297 are also active and cost only about 0.1 s and 0.3-0.66 s,
respectively, every five steps. They are not the main bottleneck.

However, `resamplingEnable=true` additionally executes the complete legacy
weighted-resampling pipeline on the CPU every step. Before this pipeline, the
resident particle state is downloaded to the host. The CPU path then performs
its own population guard, global donor/receiver transfer planning, extraction,
insertion, remap, thermal renormalization and particle mass guard. Thus the CUDA
guard and CPU support correction overlap rather than forming one resident CUDA
pipeline.

`MPCD_CUDA_RESAMPLING_PERSISTENT_0240` is not enabled by the 0434 common runner.
Enabling it would move only prepared extraction/insertion edits; it would not
move the expensive deposit, candidate construction, global transfer planner,
remap or mass guard to the GPU.

## Interpretation

The slowdown is not inherent to backward-step physics. It is an implementation
scaling problem amplified by this large, broadly populated case. Q6 is faster
because its tested path is resident CUDA, despite reaching the configured 800
iterations in the existing run. The current Q6 divergence diagnostics also show
that this Q6 run is not a clean converged physical reference.

Livevis smoothing (`50` passes), per-frame display and filtered recording add
further cost in the interactive script, but the headless profile proves that
they are not the principal resampling slowdown.

## Next engineering step

A production fix requires choosing one coherent resampling path:

1. A CUDA-local path using 0296/0297 only, explicitly disabling the legacy CPU
   weighted-resampling pipeline. This is fast but is not physically equivalent
   to the complete current algorithm.
2. Completing resident CUDA resampling: GPU cell deposit and classification,
   scalable local/compact transfer planning, and resident remap/thermal/mass
   guards. This preserves the intended complete algorithm but is a larger task.

Simply enabling the existing persistent 0240 edit flag is insufficient.
