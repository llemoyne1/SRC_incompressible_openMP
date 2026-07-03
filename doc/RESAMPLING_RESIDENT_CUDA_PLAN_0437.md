# Plan 0437: complete resident CUDA resampling

Date: 2026-07-03

## 1. Measured problem

The controlled `960 x 480`, `gamma=7` backward-step profile gives 2.90 s/step
for the complete resampling path with livevis disabled. SRC itself costs only
0.13 s/step.

The dominant costs are:

1. initial weighted-resampling CPU deposit and mutation planning: 1.05 s/step;
2. post-population-guard CPU deposit and planning: 0.76 s/step;
3. CPU particle mass guard: 0.47 s/step;
4. CPU thermal renormalization: 0.13 s/step.

The detailed deposit profile attributes about 0.97 s per planning call to
`transfer_plan_build`. The current greedy planner repeatedly scans all donor
cells while satisfying each receiver. Its cost grows poorly with the numbers
of poor and rich cells. Grid shifting in the step case creates tens of thousands
of low-population cells, exposing this scaling.

This is not an accidental CUDA failure. `resamplingEnable=true` deliberately
downloads the resident particle state and runs the complete host algorithm.
CUDA 0296/0297 execute in addition to that pipeline. Persistent path 0240 covers
only prepared extraction/insertion edits and cannot remove the expensive host
deposit, planner, remap or guards.

## 2. Required semantic decision

Two algorithms must remain explicitly distinct:

- `cuda-local`: CUDA mass reconditioning and local population guard/refill only;
- `full-resident`: the complete weighted-resampling semantics, including global
  transfer, remap, thermal correction and mass bounds.

The existing `src-resampling` name must not silently change meaning. The test
matrix in `scripts/run_0434_step_resampling_path_matrix.sh` measures both reduced
options against the current complete reference.

## 3. Code implementation stages

### Stage 0: remove duplicate host planning

Before the resident CUDA port, defer construction of the CPU mutation plan
until after the population guard. Previously, edited steps built a complete
initial plan, discarded it after the guard changed support, and rebuilt it from
the post-guard state. Patch 0437 now performs the initial deposit without a
mutation plan and builds exactly one plan from either the post-guard state or,
when the guard made no edit, the unchanged initial state.

Validation gate:

- unchanged extraction/insertion and conservation diagnostics within normal
  run-to-run variability;
- one `transfer_plan_build` per step instead of two when the guard edits;
- measured reduction of complete-path step time before changing CUDA semantics.

Checkpoint result on five step-case steps:

- elapsed: 16.64 s -> 12.91 s (-22.4%);
- internally profiled: 14.55 s -> 11.01 s (-24.3%);
- initial transfer-plan construction: 5.11 s -> 0;
- post-guard transfer-plan construction: one plan per step, 5.10 s total;
- insertion mass residual: 0;
- no missing pool slots or non-inactive insertion sources;
- remap and thermal momentum residuals <= `1.34e-15`.

The final fluid count differed by one particle between the two runs, below the
already measured inter-run CUDA variability. Stage 0 is therefore enabled by
default in the rebuilt livevis binary.

### Stage A: resident device deposit with unchanged classification

Implement a CUDA weighted-deposit adapter consuming
`cuda_shared_particle_state_0251` directly. Produce device arrays for count,
mass, momentum, mean velocity, active/wet/poor/rich masks and global diagnostics.
Reuse the persistent cell workspace where layouts are compatible.

Validation gate:

- CPU/CUDA cell arrays on frozen TG, Poiseuille, box and step states;
- identical active/wet/poor/rich counts;
- mass and momentum agreement near floating-point reduction tolerance;
- no device-to-host particle download.

### Stage B: compact candidate construction on GPU

Use flag plus prefix-scan compaction to build poor/receiver and rich/donor lists
on device. Keep the current thresholds, wet-mask semantics, Darcy chi exclusion
and deterministic cell-index ordering.

Validation gate:

- exact candidate cell lists against CPU after sorting by cell index;
- exact deficit/excess totals;
- step profiles showing deposit and candidate construction below SRC cost.

### Stage C1: exact CUDA port of the current transfer policy

Port the present nearest-donor greedy policy before changing it. Keep receiver
order, distance metric, tie-breaking and donor depletion rules. This establishes
a behavioral reference but may retain poor asymptotic scaling.

Validation gate:

- exact transfer cell pairs and close transfer masses on small deterministic
  cases;
- conservation of planned donor/receiver mass;
- no host particle-state synchronization.

### Stage C2: scalable transfer planner

Only after C1 parity, replace global repeated donor scans with a spatially
bounded planner: cell bins plus expanding local neighborhoods, or a compact
cell-graph frontier. Preserve local preference and deterministic tie-breaking.
Fall back to a global search only for unresolved receivers.

This stage changes operation ordering and can change the microscopic trajectory.
It therefore requires physical/statistical validation, not only unit parity.

Implementation checkpoint 0437: an exact expanding-ring donor search is now
implemented for non-periodic grids, with a per-selection shadow comparison
against the historical global scan. It is opt-in through
`MPCD_RESAMPLING_SPATIAL_DONOR_SEARCH_0437=1`; the shadow additionally requires
`MPCD_RESAMPLING_SPATIAL_DONOR_SEARCH_0437_SHADOW=1`. It remains disabled by
default because the GPU execution limit prevented the first shadow run after
the successful build.

Resume protocol:

```bash
MPCD_RESAMPLING_SPATIAL_DONOR_SEARCH_0437=1 \
MPCD_RESAMPLING_SPATIAL_DONOR_SEARCH_0437_SHADOW=1 \
  # run the five-step full step-case profile
```

The shadow must complete without a donor mismatch. Then rerun with only
`MPCD_RESAMPLING_SPATIAL_DONOR_SEARCH_0437=1` to measure performance. Periodic
domains intentionally retain the global planner until a periodic ring search
is implemented and validated.

Validation gate:

- bounded unresolved mass and explicit fallback counters;
- exact global mass and momentum conservation;
- population distribution, temperature and flow observables compared over
  multiple seeds;
- scaling measured versus grid size and poor/rich-cell fraction.

### Stage D: resident extraction, insertion and pool update

Consume the device transfer plan directly. Integrate extraction/insertion with
the active-prefix and inactive-pool invariants. Extend 0240 rather than creating
a second mutation implementation.

Validation gate:

- role counts and free-pool counts conserved exactly;
- no duplicate slot use;
- mass/momentum residuals at roundoff;
- no full host mirror update between summaries.

### Stage E: resident remap and thermal renormalization

Apply per-cell mass/momentum remap and relative-velocity thermal correction on
device using the resident cell-to-particle index. Keep the current target mass,
capacity gates and thermal-energy definitions.

Validation gate:

- per-cell mass/momentum/thermal residual comparison with CPU;
- TG and Poiseuille equilibrium statistics over multiple seeds;
- no systematic temperature drift.

### Stage F: resident particle mass guard

Port the bounded-mass projection per cell. This stage must preserve the affine
cell-mass constraint and cell momentum, including infeasible-cell diagnostics.

Validation gate:

- all final masses within configured bounds when feasible;
- exact guarded/infeasible cell counts against CPU on frozen states;
- mass, momentum and thermal residual tolerances unchanged.

### Stage G: orchestration and removal of duplicate work

Add an explicit backend selector such as `resamplingBackend=cpu|cuda_local|cuda_full`.
For `cuda_full`, execute one coherent resident pipeline. Disable duplicate
0296/0297 passes when their work is already included. Synchronize only for
summary, dump, recording or an unsupported downstream consumer.

Validation gate:

- phase trace proves no CPU weighted-resampling phases and no per-step particle
  download;
- strict mode fails immediately if any requested resident stage is unsupported;
- existing CPU mode remains unchanged as a reference.

## 4. End-to-end physical validation

Run classic CPU-reference and resident CUDA resampling on TG, Poiseuille, box,
backward step and VK. Use at least three seeds where trajectory-wise equality is
not expected. Compare:

- total mass and momentum budgets;
- particle mass extrema and population histograms;
- temperature and kinetic-energy evolution;
- Q6 divergence where projection is enabled;
- Poiseuille profile error;
- backward-step recirculation length and population near the corner;
- VK shedding frequency and wake statistics.

No stage should be promoted solely from a visual comparison.

## 5. Performance acceptance targets

On the current `960 x 480`, `gamma=7` step benchmark, headless:

- no individual resampling phase above 0.13 s/step (current SRC cost);
- complete resampling overhead below 1x SRC initially, with a stretch target of
  0.5x SRC;
- no O(receiver x donor) growth in the normal local-planner path;
- stable memory usage without per-step large allocations;
- livevis and recording measured separately from simulation time.

## 6. Immediate script experiments

Use:

```bash
bash scripts/run_0434_step_resampling_path_matrix.sh
```

Default matrix: `src src-q6 cuda-local cpu-reduced full`, 20 steps, headless,
with internal profiles. Useful overrides include:

```bash
CASES="cuda-local cpu-reduced full" STEPS=50 \
  bash scripts/run_0434_step_resampling_path_matrix.sh
```

The `cuda-local` and `cpu-reduced` results are performance/behavior experiments,
not substitutes for validation of the complete algorithm.

### Smoke result

The five-path matrix was executed for five headless steps on `960 x 480`,
`gamma=7`:

| Path | Elapsed | Internally profiled |
|---|---:|---:|
| SRC | 2.26 s | 1.09 s |
| SRC + Q6 | 3.65 s | 2.41 s |
| CUDA-local resampling | 2.59 s | 1.05 s |
| CPU-reduced resampling | 3.40 s | 1.60 s |
| Complete resampling | 16.64 s | 14.55 s |

The complete path spends 5.46 s in initial deposit/planning, 3.84 s in the
post-guard deposit/planning and 2.42 s in mass guard. The smoke run validates
the script branches and confirms the diagnosed bottleneck. It does not validate
long-time physical equivalence of either reduced path.
