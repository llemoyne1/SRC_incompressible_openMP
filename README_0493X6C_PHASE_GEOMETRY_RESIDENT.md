# 0493x6c — resident phase geometry scaffold

## Purpose

0493x6c turns the diagnostic geometry work of 0493x6b into reusable CUDA-resident
infrastructure, without changing the Q6 operator or particle trajectories.

The long-term target is one phase-aware incompressible/compressible path shared by
multi-species Q6, external gas pressure, Darcy/chi boundary classification and
surface tension.  This patch deliberately stops before any of those consumers are
connected.

## Resident fields

When `MPCD_Q6_PHASE_GEOMETRY_RESIDENT_0493X6C=1` and the current path is
`free_surface_masked`, two `double[numCells]` buffers are materialized once per Q6
solve:

1. `phaseFillRaw0493x6c`: normalized total mass of all species whose
   `phaseFamily=liquid`,
2. `phaseAlphaFiltered0493x6c`: one conservative five-point smoothing step of the
   raw field.

The raw field is

`raw[c] = sum_s(liquid) M_s[c] / sum_s(liquid) M_ref,s`.

No per-particle pass is added.  The existing resident species-cell mass deposit is
reused.

## Conservative filter

The filtered field is

`alpha[c] = raw[c] + lambda * sum_face_neighbours(raw[nb] - raw[c])`

with fixed scaffold value `lambda=0.125`.  Periodic neighbours wrap.  At a
non-periodic domain boundary the missing face contributes no flux.  The stencil is
therefore pairwise conservative on the Cartesian grid, and its central weight is
non-negative (`>= 0.5`).

This is a geometry regularizer, not a physical diffusion process and not yet a
bounded VOF reconstruction.  No new production parameter is introduced at this
stage; the fixed filter is being qualified before exposing any tuning.

## Cost contract

The permanent candidate cost introduced by x6c is exactly two O(numCells) CUDA
passes per free-surface Q6 solve:

- aggregate all liquid species into the raw phase field,
- conservative local filter.

No face-coefficient array and no normal/curvature array is stored yet.  Future
cut-cell coefficients should be built from the resident filtered field in, or
fused with, the Q6 RHS/operator preparation rather than adding another permanent
geometry pass.

At step 1 and the existing `summaryEvery` cadence only, a third audit kernel checks
conservation, interface geometry and GPU kernel timings.  The audit is not part of
the intended production cost.

## Physics contract

0493x6c does **not** alter:

- the current `free_surface_masked` support,
- the current half-cell zero-gauge interface condition,
- Q6 CG coefficients or RHS,
- gas pressure coupling,
- SRC collisions,
- body force, streaming or thermostat,
- resampling,
- external boundary-condition handling,
- Darcy/chi handling.

The resident geometry is read-only infrastructure in this patch.

## Future use

The filtered phase field is intended to become the single geometric source for:

- cut-cell/ghost-fluid Q6 interface metrics,
- `p_liquid = p_gas` pressure coupling,
- interface normals,
- curvature and `sigma*kappa` surface tension,
- phase-level aggregation when several species belong to one mechanical phase.

External walls, open boundaries and Darcy/chi must remain separate face
classifications combined with this phase geometry; x6c does not reinterpret them.
