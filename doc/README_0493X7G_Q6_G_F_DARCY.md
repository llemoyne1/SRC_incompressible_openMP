# 0493x7g — Q6-g-f + resident Darcy/chi

## Purpose

0493x7g extends the qualified Q6-g-f path from 0493x7f to the existing
CUDA-resident Darcy/chi fictitious-domain representation of solids.  No new
immersed-solid reflection geometry, piston or moving-domain path is introduced.

The central ordering requirement is that a deterministic Brinkman velocity
source must not be applied after the incompressibility projection and then used
for transport.  In Q6-g-f the qualified x7g step therefore becomes:

```text
resident state after previous SRC/collision
  -> deterministic Darcy/Brinkman cell-mean relaxation
  -> Q6-g-f tentative body-force deposit
  -> x6f/x6g/x7d CG projection
  -> B1 fused body-force + Q6 application
  -> streaming / resident boundary path
  -> SRC collision (+ optional chi collision VP)
  -> thermostat
```

The historical post-collision Darcy location is preserved for every non-Q6-g-f
path.  Q6-g-f skips that later Darcy application so the source is neither
applied twice nor allowed to recreate divergence after projection.

## Qualified Darcy subset

The first Q6-g-f Darcy qualification is deliberately conservative:

- `darcyBrinkmanEnable=true`;
- `darcyBrinkmanForcingMode=mean|classic|cell_mean` and the established
  `mean_outward_bath|mean_oriented_bath|brinkman_outward_bath` family;
- `darcyInitialDeactivateBelowChi < 0` is mandatory;
- chi remains a fictitious-domain field and particles are not removed from the
  solid region;
- analytic and file chi remain production capabilities; the x7g matrix uses the
  file path because that is the route used by general NACA/backward-step/other
  imported geometries;
- optional `darcyChiCollisionVpEnable` remains in the existing resident SRC
  collision stage and is exercised by one matrix case;
- pure bath variants without the Brinkman mean relaxation remain unqualified by x7g;
- immersed-solid masks/reflections, moving domains and pistons remain excluded;
- resampling scope is not broadened by this patch.

The no-deactivation restriction is important for `free_surface_masked`: turning
chi-solid cells into inactive particle holes would create a support boundary
that could be confused with the physical liquid/gas interface.  Brinkman
penalization instead keeps the fictitious fluid support and damps its velocity
inside chi-solid regions.

## CUDA-resident implementation

0493x7g reuses `cuda_darcy_brinkman_0343` unchanged at the kernel level.  Its
mean mode computes the existing exact per-step relaxation
`lambda = 1-exp(-alpha*dt)` from chi/alpha and applies one collective cell-mean
velocity increment to the resident particles, preserving relative thermal
fluctuations.

The only operator-routing change is the call site in `src_mpcd_base.cpp`: Q6-g-f
runs the qualified Darcy source immediately before its prestream projection.
For the production `mean_outward_bath` family this keeps the complete existing
resident Darcy kernel upstream of Q6; Q6 changes cell means, not the intended
particle-scale thermal scatter.  The shared 0251
particle state remains authoritative.  No host synchronization is inserted.

The Darcy CSV gains one audit column:

```text
q6GfPrestream
```

It is `1` only for the new pre-Q6-g-f Darcy call.  The existing
`q6ResidentInputFresh` field deliberately keeps its old meaning for historical
w7 validation; in x7g Darcy is upstream of Q6, so `particleUploadSkipped=1` and
`q6GfPrestream=1` are the relevant resident-ordering checks.

## Qualification matrix

Default command:

```bash
LIVE_PROGRESS=1 bash scripts/run_0493x7g_q6_g_f_darcy_validation.sh
```

The compact matrix exercises Darcy with every static x7f family and an
additional production-like `mean_outward_bath` + chi-collision-VP case:

```text
periodic_darcy
channel_darcy
closed_box_darcy_gravity
io_fullface_x_darcy
io_fullface_y_darcy
io_segmented_lr_darcy
io_segmented_sameface_darcy
io_segmented_lr_darcy_chivp
```

The runner generates a horizontal and a vertical two-phase state plus two
float32 circle chi fields.  The circle is wholly inside the initial liquid half,
so the test isolates solid penalization from the physical gas interface.

The checker requires, for every case:

- requested final step and successful launch;
- expected Q6 boundary family and zero CPU fallback;
- resident `free_surface_masked` Q6 with x7d density relaxation;
- x6c geometry, x6f interface coverage and x6g EOS pressure audits;
- a final Darcy row at the same step with `q6GfPrestream=1`;
- resident Darcy reuse (`particleUploadSkipped=1` after the initial step);
- nontrivial finite chi/alpha/solid-leak diagnostics;
- strict successful execution of the optional chi-collision-VP case.

A longer `STEPS=500` repeat is intended before freezing x7g and updating the
project report/inventories.
