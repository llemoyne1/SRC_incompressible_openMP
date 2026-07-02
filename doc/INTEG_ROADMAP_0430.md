# INTEG 0430 - CUDA resident integration roadmap

Date: 2026-06-25
Working tree: `/mnt/e/SRC_MPCD_DEV/SRC_GPU-INTEG`
Source baseline: `/mnt/e/SRC_MPCD_DEV/SRC_GPU-Q6-CUDA`

## Objective

Generalize the validated CUDA-resident simulation capabilities to four retained
paths:

1. `SRC`
2. `SRC-resampling`
3. `SRC-Q6`
4. `SRC-Q6-resampling`

The target capability matrix is:

- CL periodic;
- CL wall;
- full-face inlet/outlet;
- segmented inlet/outlet;
- Darcy open/thermal/chiVP controls.

The integration must preserve the physical operation order and avoid host/device
round-trips in the hot loop unless they are explicitly part of a validated
fallback path.

## Scientific constraints

The retained model family is the MPCD/SRD collision-streaming method with
thermalization and optional incompressible projection. The integration must keep
the validated operation order and stochastic-cell semantics rather than merely
matching macroscopic summaries.

Reference principles:

- Malevanets and Kapral, 1999: stochastic rotation dynamics/MPCD as a
  particle-based mesoscopic fluid method.
- Ihle and Kroll, 2001/2003: Galilean invariance and random grid shifting in
  SRD/MPCD.
- Lamura et al., 2001: thermal wall and boundary treatment context for SRD.
- Chorin, 1968, and Harlow and Welch, 1965: projection/MAC finite-volume
  incompressibility structure for Q6.
- Standard conjugate-gradient requirements: symmetric positive operator on the
  gauge-fixed subspace; boundary flux compatibility for Neumann/open cases.

Practical implication: a CUDA path is not accepted because it runs; it is
accepted only after comparison against the existing validated reference for the
same geometry, operation order, and enabled physics.

## Current baseline findings

The source tree already contains several resident CUDA paths, but they are
intentionally guarded:

- `srcClassicCudaModeEnable=true` selects the classic SRC CUDA path and
  currently short-circuits Q6/resampling in the main driver.
- `darcyBrinkmanEnable=true` currently requires `srcClassicCudaModeEnable=true`
  and `projectionEnable=false` in parameter validation.
- resident `SRC-Q6` periodic is guarded by
  `MPCD_CUDA_Q6_RESIDENT_SRC_STEP_0401=1` and rejects resampling.
- resident `SRC-Q6` full-face inlet/outlet is guarded by
  `MPCD_CUDA_Q6_RESIDENT_SRC_IO_FULLFACE_0404=1` and rejects resampling,
  masks, and capacity coupling.
- resident `SRC-Q6` segmented inlet/outlet is guarded by
  `MPCD_CUDA_Q6_RESIDENT_SRC_IO_SEGMENTED_0409=1`; current documentation marks
  it as a smoke implementation, not full CPU/CUDA parity.
- Darcy/chiVP is implemented in the persistent CUDA SRC collision path, with
  fast defaults added in the 0426 scripts, but its parameter validation still
  forbids simultaneous Q6.

These guards are useful evidence, not clutter. Removing them globally would
make unvalidated combinations look supported.

## Integration rule

Do not add a new routing layer, new simulation parameters, or new environment
flags unless a capability cannot be expressed by the existing model parameters.
The existing inputs remain the source of truth:

- `srcClassicCudaModeEnable`;
- `resamplingEnable`;
- `projectionEnable` / `projectionBackend`;
- boundary-condition parameters and open-boundary segments;
- Darcy/chi/chiVP parameters.

The integration work consists of removing historical exclusivity guards when the
corresponding combination is implemented and validated. Unsupported combinations
may still fail closed, but the failure should come from the existing validation
path and should be removed once the path is supported. Avoid adding persistent
diagnostic surfaces beyond the summaries already needed by validation scripts.

## Capability matrix

Initial status in the baseline:

| Path | periodic | wall | inlet/outlet full | inlet/outlet segmented | Darcy open/thermal/chiVP |
| --- | --- | --- | --- | --- | --- |
| SRC | existing resident variants | existing resident variants | existing resident 0263 | existing resident 0264 | existing SRC-classic CUDA path |
| SRC-resampling | partial CUDA resampling support | partial | partial, guarded | partial, guarded | requires chi filter; needs explicit validation |
| SRC-Q6 | validated periodic 0401 | needs staged validation | validated full-face 0404 | smoke only 0409 | currently blocked by params validation |
| SRC-Q6-resampling | currently blocked | blocked | blocked | blocked | not validated |

## Proposed validation sequence

### Step 1 - Guard audit and first restriction removal

Audit each restriction that prevents combining the retained capabilities and
remove only the first narrow guard whose downstream operation order is already
implemented.

Exit criteria:

- existing validated scripts still build and run;
- the newly allowed combination is selected by existing parameters, not by a new
  flag;
- no new diagnostics or routing layer are added.

### Step 2 - Darcy with SRC and SRC-resampling

Keep `projectionEnable=false`. Consolidate Darcy fast flags and chi-filter
requirements for both `SRC` and `SRC-resampling`.

Exit criteria:

- backward-step Darcy/chi smoke reproduces the 0426 fast behavior;
- resampling-on case validates mass/population diagnostics with
  `cudaResamplingChiFilterEnable=true`;
- no Q6 changes in this step.

### Step 3 - Q6 boundary parity before resampling

Extend/validate `SRC-Q6` for wall and segmented inlet/outlet before enabling
resampling.

Exit criteria:

- wall case CPU-Q6 vs CUDA-Q6 parity;
- segmented inlet/outlet has a reference comparison, not only a smoke run;
- diagnostics preserve finite-volume flux balance and momentum correction.

### Step 4 - Q6 plus Darcy ordering

Define and validate the physical order for Darcy/chiVP and Q6. Candidate order:

```text
stream/boundary -> SRC collision with chiVP -> Darcy/Brinkman correction -> Q6
projection -> thermostat/diagnostics
```

This order must be checked against the existing code path before implementation.
The parameter validator should only permit it after a dedicated parity or
physics-regression run exists.

### Step 5 - Q6 plus resampling

Enable `SRC-Q6-resampling` only after Steps 3 and 4 are stable. The baseline
already documents sensitivity of strict comparisons when resampling changes
discrete extraction/insertion counts after small trajectory differences.

Exit criteria:

- compare distributional and conserved quantities rather than bitwise trajectory
  identity;
- keep role changes and inactive-slot bookkeeping resident;
- document acceptable tolerances per observable.

## Immediate next code change

For the next validated exchange, implement Step 1 only:

- make an explicit list of the guards blocking `SRC`, `SRC-resampling`,
  `SRC-Q6`, and `SRC-Q6-resampling`;
- choose the smallest restriction that can be removed without changing kernels;
- validate the affected existing script(s);
- do not introduce new user-facing switches.

This keeps the first code change reversible, measurable, and aligned with the
existing parameter model.

## Update 0430a - First restriction removed

Removed the `resamplingEnable=false` requirement from the common resident
`SRC -> Q6` support gate. This allows the existing periodic resident SRC/Q6
chain to run before the existing resampling stage when `resamplingEnable=true`,
without adding flags, parameters, routing layers, or kernels. The driver already
synchronizes the resident particle state before the current resampling block.

Also removed the matching shell refusal in
`scripts/run_cuda_q6_resident_src_step_tg_0401.sh`; the script now accepts
`RESAMPLING_ENABLE=true` and uses the existing run parameters.

Validation:

- Build: `bash scripts/build_src_mpcd_cuda_q6_resident_0400.sh` passed.
- Non-regression: `STEPS=20 NX=32 NY=32 GAMMA=10 RESAMPLING_ENABLE=false
  LIVE_VIS_ENABLE=0 bash scripts/run_cuda_q6_resident_src_step_tg_0401.sh`
  passed strict CPU-Q6 vs CUDA-Q6 comparison.
- New allowed mode smoke: same command with `RESAMPLING_ENABLE=true` now runs
  and applies resident Q6 (`q6Applied=1`, `q6Converged=1`, `q6Iterations=72`,
  `q6DivAfterProjectedFluxRms=2.6452958976146876e-11`), but strict global
  CPU-Q6 vs CUDA-Q6 comparison still fails on 15/76 metrics. Treat this as a
  successful restriction removal smoke, not as final validation of
  `SRC-Q6-resampling`.

Next required work: define a validation criterion for Q6 plus resampling that is
not simple trajectory equality, then move the resampling mutations themselves
further onto the resident CUDA state.

## Update 0430b - SRC-only CL/Darcy guard audit

Audit target: `srcClassicCudaModeEnable=true`, `projectionEnable=false`,
`resamplingEnable=false`, `darcyBrinkmanEnable=true`. No new user-facing flags
or parameters were added.

Findings and changes:

- Darcy itself has no CL-family guard: `try_apply_cuda_darcy_brinkman_0343()`
  consumes the shared CUDA particle state when fresh, or uploads once if needed.
- Periodic SRC resident + Darcy runs with the existing periodic resident flags.
- Wall-channel SRC resident + Darcy runs with the existing wall-simple collision
  flag `MPCD_CUDA_PERSISTENT_SRC_COLLISION_WALL_SIMPLE_0253=1`.
- Segmented IO SRC resident + Darcy already runs through 0264.
- Full-face IO left/right SRC resident + Darcy already runs through 0263.
- A real full-face CL restriction remained for bottom/top inlet/outlet: 0263
  accepted only left/right pairs in both the IO backend and the persistent
  collision support guard. This has been generalized to opposed x or y pairs.

Validation smokes after the change:

- Build: `bash scripts/build_src_mpcd_cuda_q6_resident_0400.sh` passed.
- Periodic + Darcy: `runs/integ_src_darcy_periodic_smoke_0430/output` passed.
- Wall channel + Darcy: `runs/integ_src_darcy_wall_smoke_0430_direct/output`
  passed.
- Full-face left/right + Darcy:
  `runs/integ_src_darcy_fullface_smoke_0430/output` passed.
- Full-face bottom/top + Darcy:
  `runs/integ_src_darcy_fullface_y_smoke_0430/output` passed.
- Segmented + Darcy: `runs/integ_src_darcy_segmented_smoke_0430/output`
  passed.

Each smoke wrote both `summary_runtime.csv` and `darcy_cost_0343.csv`; each
CUDA-resident SRC run wrote `cuda_persistent_src_collision_thermostat_0215.csv`.

Remaining scope note: the resident wall path validated here is the existing
wall-channel family, i.e. periodic x with solid/specular/bounceback y walls. A
fully closed all-wall box without periodic or open faces is not the same CL
family in the current CUDA streaming implementation and would require a distinct
resident streaming validation.

## Update 0430c - SRC/resampling/empty-refill with CL/Darcy

Audit target: `srcClassicCudaModeEnable=true`, `projectionEnable=false`,
`resamplingEnable=true`, `cudaResamplingEmptyRefillEnable=true`,
`darcyBrinkmanEnable=true`, with the existing chi filter kept active. No new
user-facing flag or parameter was added.

Changes:

- Removed the remaining `resamplingEnable=false` restrictions from the classic
  SRC resident support gates for periodic, wall-channel, full-face IO and
  segmented IO.
- Removed `resamplingEnable=false` from the shared persistent
  collision/thermostat continuation check. Resampling is not an immediate
  downstream host consumer there; the existing pipeline synchronizes the shared
  CUDA particle state immediately before the weighted resampling block.
- Made the existing parameter `cudaResamplingEmptyRefillEnable=true` sufficient
  to request CUDA population guard 0297 when `resamplingEnable=true`. The legacy
  `MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297` env request remains supported.
- Kept the existing Darcy+resampling validation requiring
  `cudaResamplingChiFilterEnable=true`. This is a physical guard: without it,
  empty-refill/resampling could repopulate chi-solid or Brinkman-excluded cells.
- Kept fused stream-deposit 0274 outside this step. It is a separate fused
  streaming+deposit path and is not required to unlock SRC/resampling/empty-refill
  for the CL/Darcy families.

Validation:

- Build: `bash scripts/build_src_mpcd_cuda_q6_resident_0400.sh` passed after the
  final guard correction.
- Periodic Darcy + resampling + empty-refill:
  `runs/integ_src_resamp_empty_darcy_periodic_smoke_0430/output`.
- Wall-channel Darcy + resampling + empty-refill:
  `runs/integ_src_resamp_empty_darcy_wall_smoke_0430/output`.
- Full-face bottom/top Darcy + resampling + empty-refill:
  `runs/integ_src_resamp_empty_darcy_fullface_y_smoke_0430/output`.
- Segmented left/right Darcy + resampling + empty-refill:
  `runs/integ_src_resamp_empty_darcy_segmented_smoke_0430/output`.

CSV audit:

- `cuda_resampling_population_guard_0297.csv`: all four cases report
  `handled=1`, `cudaAvailable=1`, `sharedStateFreshBefore=1`,
  `chiFilterEnable=1`, `emptyRefillEnable0319=1`.
- `cuda_persistent_src_collision_thermostat_0215.csv`: all four cases report
  `sharedParticleStateEnabled=1` and `thermostatAppliedOnGpu=1` on the final
  step.
- `darcy_cost_0343.csv`: Darcy costs are produced in all four cases. Final-step
  active fluid counts are 10240 periodic, 4608 wall-channel, 4992 full-face
  bottom/top, and 4604 segmented.
- `summary_runtime.csv`: all four cases report `resampComputed=1`. The CPU
  population guard applies in the wall-channel smoke (`resampPopulationGuardApplied=1`);
  the other three are access/non-regression smokes where the configured local
  guard has no CPU population edit on the final step.

Important interpretation:

These smokes validate access to the combined path and resident state handoff,
not a deliberately forced empty-cell refill event. In the 0297 CSV, all four
cases have `emptyRefillCandidates0319=0` and `emptyRefillParticles0319=0`.
That is acceptable for this restriction-removal step: empty-refill is requested,
chi-filtered, and executed with a fresh shared CUDA state, but the tested
states do not contain eligible empty cells needing refill. A separate validation
should construct or select a void-rich state to prove positive insertion by
empty-refill under periodic, wall, full-face IO, and segmented IO.

## Update 0431 - SRC+Q6 access to CL/Darcy and integrated scripts

Audit target: `srcClassicCudaModeEnable=false`, `projectionEnable=true`,
`projectionBackend=cuda`, with the same resident CUDA CL/Darcy families already
opened for SRC classic. No new simulation parameter was added. The only new
script-level selector is the execution switch `INTEG_PATH` or `RUN_MODES` with:
`src`, `src-resampling`, `src-q6`, `src-q6-resampling`.

Changes:

- Removed the remaining parameter validation that forced
  `darcyBrinkmanEnable=true` to require `srcClassicCudaModeEnable=true`.
- Generalized resident Q6 open-boundary handling from the earlier limited
  x/full-face and left-segment case to:
  periodic, wall-channel, full-face x or y inlet/outlet pairs, and segmented
  open boundaries on any face.
- Added the SRC+Q6 segmented resident support gate so
  `MPCD_CUDA_Q6_RESIDENT_SRC_IO_SEGMENTED_0409=1` can use the existing
  segmented IO resident path instead of falling back.
- Kept the Q6 thermostat after projection. The scripts therefore disable the
  older SRC fused thermostat env only for Q6 modes, so the operation order
  remains collision -> Q6 projection -> thermostat.
- Added a CPU fallback repair for the thermostat consumer when Q6 resident has
  changed the active prefix and the collision `cellId` buffer no longer matches
  `active_fluid_count_size(state)`. The fallback rebuilds active cell ids with
  the collision grid shift before applying the CPU thermostat.
- Updated the Darcy scripts
  `run_src_classic_cuda_darcy_chi_vonkarman_periodic_0416.sh`,
  `run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`,
  `run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`, and
  `run_src_classic_cuda_darcy_chi_backward_step_0425.sh` with autonomous
  `INTEG_PATH` selection.
- Updated `run_portable_tg_hole_resampling_0337_livevis.sh` and
  `run_portable_poiseuille_resampling_0337_livevis.sh` with autonomous
  `RUN_MODES` selection over the four integrated paths.

Validation:

- Syntax: all six updated scripts pass `bash -n`.
- Build: `bash scripts/build_src_mpcd_cuda_q6_resident_0400.sh` passes.
- Wall-channel Q6: `runs/integ_script_poiseuille_q6_smoke_0431b/src-q6/output`
  reports `q6Applied=1`, `q6Converged=1`, `thermostatApplied=1`.
- Periodic Q6: `runs/integ_script_tg_hole_q6_smoke_0431b/src-q6/output`
  reports `q6Applied=1`, `q6Converged=1`, `thermostatApplied=1`.
- Segmented Darcy Q6:
  `runs/integ_script_backward_q6_smoke_0431d/output` reports
  `q6Applied=1`, `q6Converged=1`, `q6OpenBoundaryEnabled=1`,
  `thermostatApplied=1`, and writes `darcy_cost_0343.csv`.
- Wall-channel Q6+resampling:
  `runs/integ_script_poiseuille_q6_resampling_smoke_0432/src-q6-resampling/output`
  reports `q6Applied=1`, `q6Converged=1`, `thermostatApplied=1`,
  `resampComputed=1`.
- Periodic Q6+resampling:
  `runs/integ_script_tg_hole_q6_resampling_smoke_0432/src-q6-resampling/output`
  reports `q6Applied=1`, `q6Converged=1`, `thermostatApplied=1`,
  `resampComputed=1`.
- Segmented Darcy Q6+resampling:
  `runs/integ_script_backward_q6_resampling_smoke_0432/output` reports
  `q6Applied=1`, `q6Converged=1`, `q6OpenBoundaryEnabled=1`,
  `thermostatApplied=1`, `resampComputed=1`, and writes `darcy_cost_0343.csv`.
- Full-face Q6 code path is generalized in the resident Q6 and resident IO
  predicates, but it is not used as the backward-step validation criterion here:
  the physically relevant backward-step script uses segmented inlet/outlet, and
  that path passes in both Q6 and Q6+resampling.

Important interpretation:

The smoke validations are access and non-regression tests, not physical
equivalence proofs between SRC, SRC+resampling, SRC+Q6, and
SRC+Q6+resampling. Those four paths intentionally do not represent exactly the
same physics. Quantitative comparison must be done path-by-path against a
matching reference where available. The current step establishes that SRC+Q6
and SRC+Q6+resampling no longer hit the previous CL/Darcy launch restrictions
for the tested periodic, wall-channel, and segmented Darcy families. For
backward-step Darcy, the validated CL is the segmented IO configuration; the
full-face ablation script is not treated as a required reference for this
simulation option.

## Update 0432 - Short-grid comparison and resident-path audit

Scope: compare the integrated paths `src`, `src-resampling`, and
`src-q6-resampling` on short grids for TG, Poiseuille, backward-step Darcy, and
segmented box IO. The comparison is a launch/access audit and a sanity check,
not a physical equivalence proof across paths.

Script correction made during the audit:

- Q6 modes in the portable TG, Poiseuille, segmented-box, and backward-step
  scripts now export `MPCD_CUDA_Q6_RESIDENT_THERMOSTAT_0400=1`.
- The same Q6 helpers force the existing resident collision flags:
  `MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=1`,
  `MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251=1`, and the corresponding
  strict flags.
- No new simulation parameter was introduced.

Initial comparison, 50 steps:

| case | path | elapsed | slowdown vs SRC | main observation |
| --- | ---: | ---: | ---: | --- |
| TG with inactive hole | SRC | 0.57 s | 1.00 | stable, kBT ~1.56e-3 |
| TG with inactive hole | SRC+resampling | 0.74 s | 1.30 | stable, but inactive pool participates in resampling |
| TG with inactive hole | SRC+Q6+resampling | 0.96 s | 1.68 | aberrant before fix, kBT ~6.70e3 |
| Poiseuille wall | SRC | 0.58 s | 1.00 | stable, meanVx ~1.893e-2 |
| Poiseuille wall | SRC+resampling | 0.74 s | 1.28 | stable, close to SRC |
| Poiseuille wall | SRC+Q6+resampling | 0.86 s | 1.48 | stable, kBT ~9.27e-4 before thermostat env fix |
| Backward-step Darcy segmented | SRC | 0.65 s | 1.00 | stable, Darcy mean speed ~0.245 |
| Backward-step Darcy segmented | SRC+resampling | 1.10 s | 1.69 | stable, same mean flow as SRC |
| Backward-step Darcy segmented | SRC+Q6+resampling | 1.51 s | 2.32 | passes, but physically different: kBT ~7.6e-3, Darcy speed ~0.106 |
| Segmented box IO | SRC | 0.68 s | 1.00 | stable, kBT ~0.971 |
| Segmented box IO | SRC+resampling | 0.96 s | 1.41 | stable, larger active population |
| Segmented box IO | SRC+Q6+resampling | 1.14 s | 1.68 | passes, but cools strongly: kBT ~7.2e-2 |

TG normal without hole was rerun by moving the inactive-hole rectangle outside
the domain. Before the resident thermostat correction, `src-q6-resampling`
remained aberrant even without a hole (`kBT ~6.75e2`), so the hole was not the
sole cause. After the resident thermostat/collision env correction, the same
TG normal short run reports:

- `kBT=6.073e-04`, `resM=1.82e-01`, `q6=3.92e-11`, wall time ~0.7 s.
- Environment audit: `MPCD_CUDA_Q6_RESIDENT_0400=1`,
  `MPCD_CUDA_Q6_RESIDENT_THERMOSTAT_0400=1`,
  `MPCD_CUDA_PERSISTENT_SRC_COLLISION_USE=1`, and
  `MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251=1`.

Post-fix Q6+resampling short reruns:

| case | post-fix final line |
| --- | --- |
| TG normal | `kBT=6.073e-04`, `stdN=2.279`, `resM=1.82e-01`, `q6=3.92e-11`, wall ~0.7 s |
| Poiseuille wall | `kBT=1.136e-03`, `stdN=4.869`, `resM=1.93e-01`, `q6=5.45e-11`, wall ~0.6 s |
| Backward-step Darcy segmented | `kBT=7.557e-03`, `stdN=3.156`, `resM=6.38e-01`, `q6=1.45e-02`, wall ~1.1 s |
| Segmented box IO | `kBT=7.663e-02`, `stdN=4.608`, `resM=3.22e-01`, `q6=2.58e-09`, wall ~1.0 s |

Resident-path interpretation:

- The post-fix logs contain no explicit `fallback`, `cpu fallback`, or `atomic`
  marker in the audited run trees.
- The generated environment snapshots confirm Q6 resident projection,
  Q6 resident thermostat, and resident persistent collision flags are active
  for the Q6+resampling reruns.
- The legacy `cuda_persistent_src_collision_thermostat_0215.csv` reports
  `thermostatAppliedOnGpu=0` for Q6 modes because the older SRC fused thermostat
  is intentionally disabled there. This should not be read as a CPU fallback by
  itself; the active Q6 thermostat is controlled by
  `MPCD_CUDA_Q6_RESIDENT_THERMOSTAT_0400`.

Open scientific points:

- TG and Poiseuille are no longer numerically explosive after the script fix.
- Backward-step Darcy with segmented IO and Q6+resampling still produces a
  materially different flow state from SRC/SRC+resampling. This is not a launch
  failure, but it is not validated as physically equivalent.
- Segmented box IO with Q6+resampling still cools strongly relative to SRC.
  This remains a physical validation issue for the Q6/open-boundary/resampling
  coupling, not a shell-script access issue.

## Update 0433 - Resampling block includes mass guard and empty-refill

Rule retained for the integrated scripts: every path whose selector contains
`resampling` enables the full CUDA-resident resampling block:

- CUDA mass reconditioning 0296:
  `MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296=1`.
- CUDA population guard 0297:
  `MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297=1`.
- CUDA empty-refill 0319:
  `cudaResamplingEmptyRefillEnable=true` in the parameter file and
  `MPCD_CUDA_RESAMPLING_EMPTY_REFILL_0319=1` in the environment.

The same scripts set these controls to zero on non-resampling paths. No new
simulation flag was introduced; the change only binds existing CUDA-resident
controls to the already selected integrated path. The default empty-refill
settings are conservative and match the earlier retained validation choice:

- `cudaResamplingEmptyRefillReference=gamma`
- `cudaResamplingEmptyRefillTargetFraction=0.1`
- `cudaResamplingEmptyRefillMemoryMaxAge=1000`

Scripts aligned:

- `run_portable_tg_hole_resampling_0337_livevis.sh`
- `run_portable_poiseuille_resampling_0337_livevis.sh`
- `run_portable_box_segmented_x0_resampling_0337_livevis.sh`
- `run_src_classic_cuda_darcy_chi_backward_step_0425.sh`
- `run_src_classic_cuda_darcy_chi_lr_segments_0411.sh`
- `run_src_classic_cuda_darcy_chi_naca_periodic_0414.sh`
- `run_src_classic_cuda_darcy_chi_vonkarman_periodic_0416.sh`

Validation:

- `bash -n` passes for the seven scripts above.
- Short generated-input smokes pass for TG `src-resampling`, Poiseuille
  `src-q6-resampling`, segmented box `src-q6-resampling`, and backward-step
  Darcy `src-q6-resampling`.
- The generated `.kv` files for these smokes contain
  `resamplingEnable=true` and `cudaResamplingEmptyRefillEnable=true`.
- The environment snapshots contain
  `MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296=1`,
  `MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297=1`, and
  `MPCD_CUDA_RESAMPLING_EMPTY_REFILL_0319=1`.
- The CUDA guard CSV confirms the 0319 path is active:
  `emptyRefillEnable0319=1`, `emptyRefillTarget0319=1`,
  `emptyRefillReference0319=gamma`, and
  `skippedBecauseStateNotFresh=0` on the audited runs.

Interpretation:

This validates activation and CUDA-resident plumbing of the full resampling
block. It does not resolve the physical validation questions already observed
for Q6+resampling on segmented Darcy and segmented box IO.

## Update 0435d - Thermal hard-reservoir CUDA segmented IO

Scope: local integration branch only. Nothing from this change has been ported
to the STRICT tree.

Root cause confirmed:

- `try_apply_cuda_classic_src_io_segmented_boundary_0264()` was already called
  before the generic segmented handler 0249b.
- `supported_segmented_0264()` nevertheless rejected every nonzero
  `inletThermalNoise`. The incomplete 0249b handler then reported `handled` and
  0435c correctly skipped the stale CPU boundary pass, but no hard-reservoir
  refill was performed.
- Removing that guard alone would have produced a zero-temperature inlet:
  kernels 0268/0269 previously assigned only the prescribed mean velocity and
  never accumulated `inletKbtNumerator`.

Implementation in `src/cuda_classic_src_io_resident_0263.cu`:

- The internal resident-IO configuration now carries effective inlet kBT,
  thermal-noise amplitude, cell-mean enforcement and thermal-rescale choices.
- Each CUDA reservoir-cell thread uses two deterministic passes over its local
  `mt19937_64`. The first computes fluctuation means and thermal energy; the
  second replays the sequence, writes particles and accumulates inlet thermal
  diagnostics. No per-particle temporary allocation or new global atomic was
  added.
- The normal generator reproduces the polar algorithm and saved-value order of
  libstdc++ `std::normal_distribution`, using the existing matching
  `mt19937_64`/uniform implementation.
- When requested, fluctuations are recentered to preserve the prescribed cell
  mean and rescaled to `2*N*kBT`, matching `boundary_base.cpp`.
- A segmented cell intersecting an inlet interval keeps the full target
  occupancy and samples positions over the complete intersected grid cell.
  This matches the cell-based CPU hard-reservoir rule and the existing CUDA
  0293 target predictor. The previous area-weighted occupation gave 40 instead
  of the CPU target 48 in the reference 12-cell, gamma=4 case; clipping particle
  positions to the exact segment also differed from the CPU cell rule.
- The obsolete thermal-noise support guards were removed for resident full-face
  and segmented hard reservoirs. No simulation parameter or environment flag
  was added.

Build validation:

- `build/src_mpcd_base_cuda_q6_resident_0400_livevis_0435d` builds successfully
  with the existing 0400 build script.
- Only pre-existing unused-function warnings are emitted.

Targeted left-inlet/right-outlet validation, 120x30, gamma=4, 100 steps:

| observable at step 100 | pre-0435c CPU boundary reference | 0435d CUDA 0264 |
| --- | ---: | ---: |
| inlet reservoir cells | 12 | 12 |
| inlet target particles | 48 | 48 |
| inlet particles inserted | 48 | 48 |
| inlet mean ux | 1 | 1 |
| inlet mean uy | ~4.6e-18 | ~4.3e-18 |
| inlet kBT | 0.05 | 0.05 |
| inlet backflow deleted | 0 | 0 |
| outlet particles deleted | 0 | 0 |
| fluid particles | 887 | 353 |

The boundary thermodynamics and hard-reservoir insertion are therefore
validated at the recorded step, and the stale shared-state crash is absent.
Global trajectory equivalence is not yet validated: the current comparison
runner forces persistent CUDA collision, while the pre-0435c reference binary
reports that this backend is unavailable under the same environment. The
remaining population difference must be isolated with matched collision and
thermostat backends before 0435d can be declared physically equivalent or
ported to STRICT.

### Update 0435d validation ablation and completeness routing

The injection/fill validation runner now preserves explicit values of the
existing 0264, 0249b and persistent collision/thermostat environment controls
across its environment reset. Defaults are unchanged. This enables controlled
backend ablations without adding a simulation option.

A matched ablation used the same 0435d binary, initial state, CPU collision and
disabled thermostat. Only the boundary backend changed:

- CPU: generic streaming and `apply_boundary_conditions()`.
- CUDA: resident segmented stream/boundary 0264.

At step 1 both paths report exactly:

- 12 inlet reservoir cells and target 48 particles;
- 37 reservoir deletions and 48 insertions;
- inlet net delta 10 and 58 active fluid particles.

The 100-step individual trajectories diverge (`887` versus `353` active fluid
particles for the tested realization). Particle dumps show that the stochastic
particle ordering/RNG consumption diverges after the first generated particle,
so trajectory identity is not an appropriate validation criterion. An ensemble
comparison over matched seeds remains required before claiming statistical
equivalence. The requested multi-seed GPU run could not be completed in this
stage because external GPU execution became unavailable.

The authoritative routing was nevertheless corrected independently of that
statistical validation:

- 0249a/0249b are not complete hard-cell-density reservoir implementations.
- `src_mpcd_base.cpp` now excludes them whenever a hard inlet reservoir is
  requested.
- A hard-reservoir CPU boundary skip can therefore only be authorized by the
  complete resident 0263/0264 path. If that path is unsupported, execution uses
  the complete CPU boundary instead of accepting partial CUDA physics.

This adds no user switch. The final 0435d binary compiles successfully after
the routing change. STRICT remains unchanged.

### Final 0435d integrated left/right smoke matrix

A final autonomous matrix used a 48x16 grid, gamma=4, 20 steps, a four-cell
high left inlet, a full-height right outlet, hard-cell-density refill and
`kBT=0.05`. All four integrated paths completed without stale shared state,
fatal error, unsupported path or logged CPU fallback:

| path | fluid particles | inlet target/inserted | inlet kBT | global kBT | Q6 residual |
| --- | ---: | ---: | ---: | ---: | ---: |
| SRC | 33 | 32/32 | 0.05 | 0.04916 | n/a |
| SRC+resampling | 33 | 32/32 | 0.05 | 0.04916 | n/a |
| SRC+Q6 | 32 | 32/32 | 0.05 | 0.04690 | 8.24e-11 |
| SRC+Q6+resampling | 41 | 32/32 | 0.05 | 0.03708 | 8.21e-11 |

For both resampling paths the environment audit confirms:

- `MPCD_CUDA_RESAMPLING_MASS_RECONDITION_0296=1`;
- `MPCD_CUDA_RESAMPLING_POPULATION_GUARD_0297=1`;
- `MPCD_CUDA_RESAMPLING_EMPTY_REFILL_0319=1`.

The runtime summary also reports `resampPopulationGuardApplied=1` and a mass
relative residual of approximately `1.1e-16`. The injection/fill runner had
previously retained zero values established by its environment reset for the
first two controls; it now activates the complete resident resampling block
unconditionally whenever the selected path includes resampling.

Runner autonomy was corrected as well: `RUN_ROOT` cleanup now occurs before
initial-state generation. An `INIT_ROOT` located below `RUN_ROOT` is therefore
no longer generated and then accidentally deleted.

Conclusion for access restrictions: complete resident hard-reservoir
left/right CUDA is available through 0264 for the four integrated selectors,
including thermal injection and the complete resampling block. Incomplete
0249a/b handlers cannot mask an unsupported hard-reservoir case. This smoke
matrix validates plumbing, conservation diagnostics and short-run numerical
finiteness; long-run/ensemble physical equivalence remains a separate
validation requirement and is not claimed here.

## Update 0435e - 8x4 algorithmic access campaign

The eight 0434 autonomous runners were exercised for 300 steps on all four
integrated paths. After correcting only the inactive-pool sizing of the two
net-injection campaign cases, the final matrix passes 32/32 with no stale state,
unsupported path, explicit CPU fallback, non-finite value or fatal error.

All 16 Darcy combinations use `mean_outward_bath` with interface-band collision
VP. All resampling combinations activate mass recondition, population guard and
empty-refill. Full method, audit criteria, results and physical caveats are in
`doc/ALGORITHMIC_VALIDATION_0435E.md`.

## Update 0435f - Injection-fill SRC+resampling baseline

A matched 1000-step injection-fill comparison shows no numerical explosion in
SRC+resampling and a lower global kinetic-temperature estimate than SRC. The
mean population over occupied cells converges from about 28 toward the target
20 while the occupied support grows from 5 to 207 cells.

The run also exposed that the injection-fill runner kept shared thermostat
consumption disabled: CUDA guards 0296/0297 were skipped as stale and CPU
resampling generated particle masses outside the requested bounds. The runner
now uses the existing shared resident thermostat configuration and one-cell
open/solid boundary halos. Full evidence and the remaining validation gate are
documented in `doc/INJECTION_FILL_RESAMPLING_0435F.md`.
