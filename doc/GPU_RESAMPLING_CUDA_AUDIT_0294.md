# GPU resampling CUDA audit 0294 — corrected post-SRC insertion plan

## Physical decision

The mutating resampling module must **not** be inserted before the SRC collision.  The validated physical step is the classic SRC/MPCD sequence:

```text
streaming / advection
→ physical boundary conditions: walls, solids, piston, inlet/outlet
→ random grid shift internal to SRC
→ SRC rotation/collision
→ unshift / physical-grid state
→ thermostat when thermostatEnable=true
```

The resampling/support-control module is therefore interpreted as a **non-destructive statistical remeshing** of the state already produced by SRC classic, not as an additional physical creation/destruction process before collision.

The nominal insertion point for future mutating resampling is:

```text
SRC classic CUDA resident
→ optional CPU/OpenMP Q6 if that path is re-enabled later
→ optional virial/capacity stage if enabled
→ CUDA support survey / resampling on the physical, non-shifted grid
→ conservative restoration of mass, momentum and relative energy
→ final thermostat only when the resampling mutation requires it and thermostatEnable=true
```

Patch 0295 implements only the passive survey at this post-SRC point.

## Existing CUDA resampling bricks found in SRC_GPU

The branch already contains useful bricks from earlier patches:

- `include/cuda_resampling_guard.h`, `src/cuda_resampling_guard.cu`: CUDA poor/rich classification and compact transfer-plan prototypes from 0227/0228.
- `include/cuda_resampling_particle_ops.h`, `src/cuda_resampling_particle_ops.cu`: CUDA extraction/insertion particle operation prototypes from 0232/0233/0237.
- `include/cuda_resampling_persistent_active_path_0240.h`, `src/cuda_resampling_persistent_active_path_0240.cpp`: older active bridge for persistent extraction/insertion.
- `include/cuda_particle_state.h`, `include/cuda_shared_particle_state_0251.h`: shared resident particle state used by the modern full CUDA classic path.
- `include/cuda_cell_workspace.h`, `include/cuda_cell_moments.h`: reusable cell workspace and CUDA deposit of cell moments.

## Reuse decision

For 0295, the older mutating resampling bridge is deliberately **not** reused as an active path.  It belongs to a previous validation line and can be re-audited later for 0297.  The safe reusable pieces are:

1. the shared resident particle state;
2. the persistent cell workspace;
3. the CUDA cell-moment deposit;
4. the existing role convention `Fluid / Inactive / Latent`.

The new module `cuda_resampling_support_survey_0295` uses these pieces to observe the post-SRC state without modifying particles, masses, velocities or roles.

## 0295 passive survey scope

The survey computes on CUDA, on the physical non-shifted grid:

- real fluid count per cell `N_c`;
- cell mass `M_c`;
- cell momentum `P_x,c`, `P_y,c`;
- cell velocity `U_x,c`, `U_y,c`;
- relative kinetic energy per cell;
- active / solid / wet / empty / poor / rich / target-band classification.

It writes a lightweight CSV:

```text
<outputDir>/cuda_resampling_support_survey_0295.csv
```

The survey is enabled only by environment variable:

```bash
MPCD_CUDA_RESAMPLING_SUPPORT_SURVEY_0295=1
MPCD_CUDA_RESAMPLING_SUPPORT_SURVEY_0295_EVERY=10
```

No result column in `summary_runtime.csv` is changed in this patch, by design.

## Insertion point in `src_mpcd_base.cpp`

The call is inserted after:

```text
src_collision_step(...)
→ optional Q6 block, currently short-circuited by srcClassicCudaModeEnable
→ optional closed-capacity/virial block
→ thermostat block
→ keepMeanFlow block
```

and before the existing CPU weighted-resampling diagnostics/mutations.

This preserves the OpenMP/MATLAB semantics: the resampling family operates on the field produced by SRC/Q6, and not on the pre-collision particle cloud.

## Validation target

0295 is a non-mutating diagnostic.  Enabling it must not change the physical run summaries.  The validation target is therefore **CUDA survey OFF vs CUDA survey ON on the same current CUDA path**, not a new historical CPU-vs-CUDA equivalence campaign.

The runner executes short current demo cases twice and compares the final `summary_runtime.csv` rows, excluding timing/file-path fields.  It also checks that no survey CSV is produced in the OFF runs and that survey rows are produced in the ON runs.

## Next milestones

- 0296: post-SRC mass-weight reconditioning without changing support.
- 0297: post-SRC local population guard using split/merge or inactive-pool activation.
- 0298: mandatory restoration of local mass, momentum and relative energy after mutation.
- 0299: boundary-aware validation for walls, solids, circle, full-face/segmented inlet-outlet and piston/mobile wall.

## 0295 runner correction after first terminal test

The first 0295 validation script used the historical consolidated validator
`run_cuda_classic_src_resident_consolidated_0265c.sh`.  That runner still calls
the old segmented inlet/outlet validator `0264`, whose stated scope is the
pre-thermostat/no-thermostat segmented resident path.  In the current branch,
the validated segmented inlet/outlet classic CUDA path is the later
boundary-aware thermostat family `0280c`, consolidated by `0281` and included in
the full classic CUDA consolidation `0286`.

Therefore a failure in `survey_off` inside `0264` does not demonstrate a
mutation or perturbation introduced by the 0295 survey.  It means the survey
runner was testing a stale validation family.  The corrected 0295 runner now
uses the current validation families by default:

```text
0281: wall-simple, rectangle/step, full-face IO and segmented IO via 0280c;
0284: periodic circle/solid;
0285: circle + full-face inlet/outlet / Von Karman-style setup.
```

The legacy 0265c runner remains available only as an explicit opt-in diagnostic
with:

```bash
INCLUDE_LEGACY_0265C=1
```


## 0295 runner correction after second terminal test

A second terminal test still failed in `survey_off`, this time inside the
historical CPU-vs-CUDA segmented validator `0280c`, with `failed=22/76`.  Since
`surveyRows=0` in that run, the 0295 survey was not active and cannot be the
cause.  The issue is methodological: 0295 should not depend on legacy
work-package validators whose purpose is CPU-vs-CUDA backend equivalence.  Those
validators can fail before the passive survey is exercised, especially after the
later outlet-mode changes 0291/0293.

The 0295 validation runner has therefore been changed to the correct
non-perturbation protocol:

```text
current CUDA demo, survey OFF
current CUDA demo, survey ON
compare final physical summaries OFF vs ON
```

Default cases are:

```text
tg_periodic
poiseuille_wall
backward_step_io
segmented_box_same_face
von_karman_circle_io
```

This validates the actual 0295 requirement: the survey observes the post-SRC
state and writes `cuda_resampling_support_survey_0295.csv` without mutating the
particle state.

## 0295 survey activation correction after Poiseuille terminal test

The Poiseuille wall demo produced identical `summary_runtime.csv` rows for
survey OFF and survey ON, but no survey CSV rows in the ON run.  This exposed an
activation bug rather than a physical perturbation: the first C++ insertion was
guarded by `residentClassicCuda`.  That predicate is intentionally narrow and
excludes some current demo paths, including wall-simple with the physical
thermostat enabled, even though those paths still use the modern CUDA streaming,
persistent collision and thermostat components.

The survey is now gated only by
`MPCD_CUDA_RESAMPLING_SUPPORT_SURVEY_0295` and by the requested sampling period.
When the shared CUDA particle state is fresh, the survey deposits from that
resident state.  When the host state is authoritative, the survey uses only a
private survey-owned CUDA buffer; it must never refresh the process-global shared
state.  This keeps 0295 passive and post-SRC while allowing it to observe all
current short CUDA demo paths used by the OFF/ON validation runner.



### 0295c non-mutating fallback fix

The survey is forbidden to refresh or overwrite the process-global shared CUDA
particle state.  If `cuda_shared_particle_state_0251_is_fresh()` is true, the
survey deposits directly from the resident shared state.  If it is false, the
survey uploads the host mirror to a private survey-owned `CudaParticleState` and
deposits from that private buffer.  This fallback may be less authoritative for
resident CUDA cases with stale host mirrors, but it is strictly passive: it cannot
modify the state that the simulation will continue to use.  The CSV field
`uploadedHostState=1` therefore means "private survey upload", not a refresh of
the global shared CUDA state.



### 0295d Von Karman validation cadence

The Von Karman case combines immersed circle handling, hard inlet refill,
open-boundary outlet logic and a resident CUDA path.  With
`MPCD_CUDA_RESAMPLING_SUPPORT_SURVEY_0295_EVERY=10`, the survey inserts extra
CUDA synchronizations inside the run.  On this active open-boundary case, the
strict OFF/ON comparison can then diverge by a single fluid/inactive slot, even
though the survey performs no particle writes.  This is a synchronization-cadence
issue in a schedule-sensitive validation, not a resampling mutation.

The 0295 runner therefore keeps the strict Von Karman non-mutation check
summary-aligned by default:

```bash
VK_SURVEY_EVERY=${VK_SURVEY_EVERY:-$STEPS}
```

The other short cases still use `SURVEY_EVERY`.  Developers can opt into the
stronger continuous Von Karman stress test with:

```bash
VK_SURVEY_EVERY=10
```

but that mode should be interpreted as a synchronization sensitivity diagnostic,
not as the primary PASS/FAIL criterion for the passive survey.

## Mise à jour validation 0295 — suite stricte par défaut

Le critère strict du survey passif 0295 est désormais limité par défaut à quatre cas
bit-reproductibles en comparaison CUDA survey OFF / survey ON :

- Taylor--Green périodique ;
- Poiseuille wall ;
- backward step / rectangle ;
- U-box inlet/outlet segmentée.

Le cas Von Karman cercle + inlet/outlet reste disponible en diagnostic optionnel
(`RUN_VK=1`), mais il n'appartient plus au verdict strict par défaut, car le chemin
thermostaté n'est pas bit-reproductible en OFF/OFF. Pour un test strict de
non-mutation sur Von Karman, le runner force `VK_THERMOSTAT_ENABLE=0` par défaut.
`VK_THERMOSTAT_ENABLE=1` doit être interprété comme un stress test physique, non
comme un témoin bit-à-bit du caractère passif du survey.

