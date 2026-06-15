# 0340 host/device authority audit for SRC GPU and Q6 CUDA residency

## Scope

This note records the 0340 audit performed after the 0338c wall+circle shared-state correction and the 0339a live-visualization cadence reduction.

The aim is not to optimize one transfer in isolation.  The aim is to prepare a Q6 CUDA-resident architecture while keeping these three paths available:

1. SRC classic CUDA resident;
2. SRC + CUDA resampling;
3. Q6 / resampling / virial liquid closure, currently CPU or hybrid.

The VIZ and non-VIZ repositories must remain functionally aligned.  Solver-side host/device authority changes should be made in both repositories.  Live-visualization-only changes remain VIZ-specific.

## VIZ versus non-VIZ source alignment

The audited solver files are effectively aligned between `SRC_GPU` and `SRC_GPU-VIZ` after 0338c.  The only solver-adjacent difference observed in the audited set is in `cuda_shared_particle_state_0251.cpp`, where VIZ adds the snapshot helper:

```cpp
cuda_shared_particle_state_0251_download_role_filtered_snapshot_0336(...)
```

The VIZ tree also contains live visualization files, notably `cuda_live_field_0337.cu` and `live_visualization_0335.*`.  The common solver pipeline (`src_mpcd_base.cpp`, `src_collision.cpp`, `cuda_immersed_circle_0284.cu`, `cuda_persistent_mpcd_step.cu`, resampling CUDA files) is otherwise aligned in the audited sources.

## Current host/device authority model

The shared CUDA particle state 0251 carries only a coarse freshness flag:

```cpp
fresh
lastWriter
lastInvalidator
```

Important operations are:

```cpp
cuda_shared_particle_state_0251_mark_fresh(writer)
cuda_shared_particle_state_0251_invalidate(reason)
cuda_shared_particle_state_0251_is_fresh()
cuda_shared_particle_state_0251_download_if_fresh(state)
```

This is sufficient for the current 0338c bridge, but it is too coarse for a future Q6 CUDA-resident architecture.  Future work should distinguish at least:

- particle kinematics freshness: `x,y,vx,vy`;
- metadata freshness: `mass,type,role,NactiveFluid`;
- host mirror freshness;
- device state freshness;
- Q6/projection field freshness;
- resampling pool/role freshness;
- dump/summary synchronization freshness.

## Phase-by-phase authority map

| Phase | Current authority tendency | Device state effect | Host mirror effect | Notes |
|---|---|---|---|---|
| step start | host unless resident state already fresh | may invalidate device state | host treated as authoritative | `start_step_cpu_state_authoritative` invalidation is used when resident CUDA is inactive or shared state is not fresh. |
| force_stream | mixed | CUDA for selected resident paths; CPU fallback otherwise | CPU fallback writes host particles | In wall+circle 0318 validation, upstream host-side work can still force an upload before `immersed_circle`. |
| domain_bounds | host scalar computation | no particle mutation | no particle mutation | Not a major authority issue. |
| boundary_conditions | mixed | CUDA for selected IO/wall paths; CPU fallback otherwise | CPU boundary can edit particles | CPU edits invalidate shared state with `cpu_boundary_conditions_edited_particles`. |
| immersed_solid / circle | CUDA when `cuda_immersed_circle_0284` handles the case | marks shared device state fresh | host mirror may become stale | 0338b removed circle download for the opt-in wall+circle bridge. |
| src_collision | CUDA persistent path | 0338c allows collision to consume fresh shared state | host mirror remains stale unless a later consumer downloads | 0338c removes the private particle upload in collision for wall+circle classic-only runs. |
| Q6 projection | currently CPU/hybrid in this branch | requires host particle data | invalidates device state after CPU Q6 | `cpu_q6_projection_after_collision` invalidation protects the hybrid path. |
| closed-capacity virial | currently CPU/hybrid | requires host particle data | invalidates device state after CPU virial | `cpu_closed_capacity_after_collision` invalidation protects the hybrid path. |
| CPU thermostat fallback | CPU when not handled by persistent shared thermostat | requires host data | invalidates device state | 0338c avoids this in the validated classic wall+circle path by enabling the shared thermostat bridge under opt-in. |
| keep_mean_flow | CPU | requires host data | invalidates device state | Still a CPU particle pass. |
| resampling diagnostics / CUDA resampling | mixed | CUDA diagnostics can read device data; host diagnostics need sync | may require explicit barriers | Future Q6 CUDA work must decide where resampling pool state is authoritative. |
| dumps/summaries | host output | lazy device-to-host sync | host becomes up-to-date at output points | Should remain lazy and not impose per-step sync. |
| live visualization | VIZ-only, read-mostly | should not mutate physics state | should not require host mirror when CUDA field renderer is active | 0339a reduces default cadence; final-state hash validation showed no physics change. |

## Current immersed-circle upload bottleneck

After 0338c the remaining wall+circle classic bottleneck is:

```text
immersed_circle upload ~= 10.5 s / 500 steps
```

The direct reason is that, before the circle kernel, the shared 0251 device state is often not fresh because the preceding force/boundary phases can still be host-authoritative.  Therefore `cuda_immersed_circle_0284` calls:

```cpp
gpuState.upload_all(state, &particleDiag);
```

This should not be removed blindly.  Doing so would assert that the device state is fresh before the circle even when CPU force/boundary phases edited the host particles.

## Why Q6 matters

Q6 is not the direct cause of the current upload in classic-only runs.  In those runs Q6 is disabled.  The direct cause is the host-authoritative upstream work before the circle.

However, the need to preserve Q6/resampling/virial as possible CPU or hybrid continuations explains why the architecture is conservative.  Global removal of host mirrors, downloads, or invalidations would break the hybrid liquid closure path.

Therefore optimizations must be guarded by mode and by authority checks.  In particular, classic-only shortcuts must remain disabled when any of these are active:

```text
projectionEnable
resamplingEnable
closedCapacityResponseEnable
closedCapacityVirialKickEnable
non-shared thermostat fallback
keepMeanFlowEnable
```

## Recommendation

Do not start by making `force_stream` and `boundary_conditions` fully resident.  That is the risky path and overlaps with earlier fragile resident-stream/fusion attempts.

Recommended sequence:

1. Preserve 0338c as the validated wall+circle shared-state correction.
2. Preserve 0339a as the low-risk live visualization cadence correction.
3. Treat the remaining immersed-circle upload as a symptom of host-authoritative upstream phases.
4. Before Q6 CUDA residency, introduce a more explicit authority model or instrumentation that can report:
   - last device writer;
   - last host invalidator;
   - whether kinematics are fresh on device;
   - whether metadata are fresh on device;
   - whether a Q6/resampling/virial CPU barrier is active;
   - why a host download or device upload occurs.
5. Consider an opt-in, classic-only, low-risk intermediate optimization using the already available kinematics-only upload path:

```cpp
CudaParticleState::upload_kinematics_with_cached_metadata(...)
```

instead of `upload_all(...)` in `cuda_immersed_circle_0284`, but only under strict guards and only after bitwise final-state validation.  This would reduce the transfer volume without claiming that upstream phases are resident.  It is optional and may become unnecessary once Q6 and upstream phases become CUDA resident.

## Validation standard

Any host/device authority patch must be validated with:

1. internal profiles over 100 and 500 steps;
2. `particleStateHostToDeviceBytes` and `cuda_resident_phase_profile_0266.csv` checks;
3. physical summaries (`kBT`, momentum, `stdN`, wall/circle hits);
4. final-state hash comparison when possible:

```text
FINAL_STATE_IDENTICAL
```

If final states are not bitwise identical, differences must be explained and bounded before merging.
