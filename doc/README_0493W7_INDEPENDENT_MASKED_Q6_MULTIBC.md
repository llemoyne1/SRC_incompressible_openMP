# 0493w7 — Independent masked species Q6 on resident multi-BC paths

## Purpose

`0493w5` deliberately restricted `speciesQ6Mode=independent_masked` to a fully
periodic domain. `0493w7` removes that additional restriction and makes the
independent per-species solve follow every boundary topology already accepted
by the resident CUDA Q6 backend:

- periodic x/y;
- periodic-x channels with wall-like top/bottom conditions;
- full-face inlet/outlet pairs;
- segmented inlet/outlet apertures on wall-like faces;
- the same topologies with Darcy–Brinkman forcing.

The existing resident-Q6 exclusions remain unchanged. Moving or truncated
fluid domains, immersed-solid projection masks, unsupported open-boundary
configurations and closed-capacity coupling are not enabled by this patch.

## Boundary stencil

The species mask remains an internal Dirichlet pressure boundary:

```text
active species cell / inactive species cell: phi_inactive = 0
```

A physical domain boundary is not treated as an absent-species cell. It uses
the same topology as legacy resident Q6:

- periodic faces wrap;
- wall-like faces prescribe zero normal base flux and a Neumann pressure
  correction stencil;
- inlet/outlet faces use the resident Q6 prescribed normal flux;
- uncovered parts of segmented faces remain impermeable.

The masked matrix therefore omits out-of-domain neighbours on non-periodic
faces, while retaining the Dirichlet contribution for an in-domain inactive
species neighbour.

## Species boundary flux

When exactly one species has a positive declared Q6 strength, that projected
species receives the complete prescribed open-boundary flux. This is the
liquid-in-compressible-gas target configuration.

When several species are independently projected, untyped full-face and outlet
fluxes are split with the local occupancy proxy. A typed segmented inlet is
applied only to the matching particle type. This prevents the same inlet flux
from being imposed independently on every projected species.

No barycentric correction and no `fallback=common` are introduced.

## CUDA residency

All mask construction, species deposition, matrix operations, pressure solve,
correction storage, particle application and post-application redeposition stay
on the device. Only scalar diagnostic reductions cross to the host, as in
`0493w5`/`0493w6`.

The Darcy stage now recognises every writer whose label begins with
`cuda_q6_resident_0400`, including the independent-masked writer. A fresh Q6
particle state is therefore consumed directly by Darcy without a particle
upload.

## Qualification

After rebuilding the livevis CUDA binary:

```bash
LIVE_PROGRESS=1 bash scripts/run_0493w7_independent_masked_multibc_smoke.sh
```

The matrix covers periodic, wall-channel, full-face open, segmented open and
Darcy-channel cases. It requires:

- the expected resident Q6 boundary family;
- no host cell-species materialisation or full-state download;
- a converged, active and directly corrected liquid solve;
- zero active cells and zero direct Q6 correction for the gas with declared
  strength zero;
- direct reuse of the fresh resident Q6 state by Darcy.

## Remaining issue

`0493w6` showed that the current face-to-cell averaging on a partial masked
support can leave a significant post-application divergence near an internal
species interface (`islands` applied/before about 0.33). `0493w7` does not
change that operator. It extends the already diagnosed stage-1 operator to the
resident boundary families without concealing this limitation.
