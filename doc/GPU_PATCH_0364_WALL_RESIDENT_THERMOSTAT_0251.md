# GPU patch 0364 - wall resident thermostat keeps 0251 fresh

Date: 2026-06-20

## Symptom

The four-case resampling validation showed that the Poiseuille wall case produced empty CUDA resampling diagnostics:

- `cuda_resampling_population_guard_0297.csv`: 200 rows, `handled=0`, `skippedBecauseStateNotFresh=200`
- `cuda_resampling_mass_recondition_0296.csv`: 200 rows, `handled=0`, `skippedBecauseStateNotFresh=200`

The CUDA collision/thermostat path was nevertheless active (`sharedParticleStateEnabled=1`, `thermostatAppliedOnGpu=1`).

## Cause

The Poiseuille script requested wall streaming 0246 and shared SRC collision/thermostat 0260, but `cuda_classic_src_wall_resident_0261_supported()` rejected the wall-resident mode whenever `thermostatEnable=true`.

Therefore `MPCD_CUDA_CLASSIC_SRC_WALL_RESIDENT_0261=1` was present in the environment but `residentClassicCuda` remained false in `run_src_mpcd_base_step()`. The step then invalidated the shared particle state 0251 after the thermostat/mean-flow section, so 0296/0297 correctly refused to consume a stale state.

This was a residency classification bug, not a numerical failure of the population guard itself.

## Change

`src/src_mpcd_base.cpp` now allows wall-resident 0261 with a thermostat only when the physical thermostat is the validated shared CUDA path:

- `thermostatMode == cell_relative_rescale`
- `thermostatEvery > 0`
- `MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_USE=1`
- `MPCD_CUDA_PERSISTENT_SRC_THERMOSTAT_SHARED_0251_0260=1`

Other thermostat configurations remain non-resident, preserving the conservative CPU fallback behavior.

The portable Poiseuille validation script also explicitly enables:

- `MPCD_CUDA_CLASSIC_SRC_WALL_RESIDENT_0261=1`
- `MPCD_CUDA_PERSISTENT_SRC_COLLISION_SHARED_0251=1`
- shared CUDA thermostat flags through `portable_cuda_enable_thermostat_0315 1`

## Validation

Binary: `build/src_mpcd_base_cuda_topo_0343_fix0251`
SHA256: `86f388130dd071bf970b508ca0d1a9a12c2f9552d66d0cde4e0d1460f68ea7a7`

Run root: `runs/validation_4cases_18jun_poiseuille_1000_fix0251_src`

Poiseuille resampling diagnostics after the fix:

- 0297: 200 rows, `handled=200`, `sharedStateFreshBefore=200`, `skippedBecauseStateNotFresh=0`
- 0296: 200 rows, `handled=200`, `sharedStateFreshBefore=200`, `skippedBecauseStateNotFresh=0`
- 0295: 10 rows, `handled=10`, `sharedStateFreshBefore=10`

Population guard activity in the corrected Poiseuille run:

- split operations: 172
- merge operations: 8
- total mass delta versus classic at step 1000: `5.82e-10` (`6.32e-15` relative)
- final fluid particle delta versus classic: `+164`

The resampling path is therefore active and no longer blocked by stale 0251 state.
