# 0493x7f — Q6-g-f on the resident static multi-BC families

## Purpose

0493x7f generalises the qualified Q6-g-f path from the dam-break closed box to
the static boundary-condition families already implemented by the CUDA-resident
Q6/streaming backend.  It is deliberately a **boundary-path patch**, not a new
projection model.

The qualified Q6-g-f operator remains the composition already established by
x6f/x6g/x6h/x7d:

```text
resident liquid geometry (x6c/x6f2)
    -> alpha=0.5 pressure stencil (x6f + near-half fix)
    -> optional gas-interface Dirichlet pressure p_l|Gamma=p_g (x6g)
    -> density-restoring target divergence (x7d)
    -> one resident CG solve
    -> wall-face reconstruction A + affine RT0/MAC-to-particle application B1
```

with the force-aware transport ordering

```text
tentative transport moment -> Q6-g-f -> resident streaming/BC -> SRC collision -> thermostat
```

No x6f, x6g or x7d equation is changed by x7f.

## Supported scope

For `speciesQ6Mode=free_surface_masked` with
`q6ForceProjectionMode=prestream_single_fused`, x7f accepts the static resident
families already represented by the Q6 backend:

- fully periodic x/y;
- periodic-x channels with static wall-like bottom/top faces;
- the four-wall `closed_box` topology qualified in x1;
- full-face inlet/outlet pairs in x or y, with the existing resident hard-inlet,
  uniform-profile and balanced-outlet contract;
- segmented inlet/outlet configurations accepted by the existing 0264/0409
  resident path, including multi-face or same-face layouts when the base parser
  and resident backend already accept them.

x7f does not invent a new boundary configuration.  The normal base-parameter
validation and the resident stream/Q6 support tests remain authoritative.  In
particular, configurations already rejected by the code remain rejected.

The `closed_box` family is put on the same Q6-g-f footing as the other static
families.  This must not be confused with the older
`closedCapacityResponseEnable` / `closedCapacityVirialKickEnable` controller:
that separate legacy coupling remains excluded.

## Deliberate exclusions

This patch does **not** enable:

- Darcy/Brinkman/chi forcing; that requires its force to be ordered consistently
  with the pre-transport projection and is deferred to the next dedicated patch;
- analytic immersed solids or `projectionImmersedSolidMaskEnable`;
- piston or any moving/truncated fluid domain;
- previously unsupported inlet/outlet combinations;
- the legacy closed-capacity response/virial controller;
- a broader resampling domain.  The x6f-r1 resampling allowance is kept restricted
  to its previously qualified static closed-box Q6-g-f subset.

The goal is therefore to generalise **only** the validated incompressible
free-surface path across the resident static BC infrastructure.

## Zero-body-force pre-transport projection

Before x7f, the non-legacy pre-stream Q6 call was entered only if gravity or a
Taylor--Green body force was non-zero.  That condition was sufficient for the
dam-break, but it prevents an inlet/outlet-driven Q6-g-f run with zero body
acceleration from reaching x6f/x6g/x7d/B1 before transport.

x7f makes the fused pre-stream call unconditional for the qualified
`free_surface_masked` Q6-g-f path.  When the body acceleration is zero, the
fused force part is an exact zero increment; the projection remains active:

```text
u* = u^n                       (zero body force)
div(u_projected) = (rawFill - 1) / tau_rho
p_l|Gamma = p_g                when x6g is enabled
```

This is a semantic correction rather than an extra solve: Q6-g-f is a
pre-transport constraint and must operate before inlet/outlet or wall streaming
whether or not a volumetric force is present.  Historical common-Q6 fused
zero-force behaviour is unchanged.

## Implementation

The source change is intentionally small:

1. `src/params_io_base.cpp` classifies the existing static resident BC families
   for the `free_surface_masked + prestream_single_fused` path and removes the
   former closed-box-only guard.  Historical non-free-surface force-ordering
   experiments keep their old narrow topology contract.
2. `src/src_mpcd_base.cpp` requests the single fused pre-stream solve for Q6-g-f
   even when the body-force field is zero.
3. `src/cuda_q6_resident_0400.cu` permits that zero-force fused invocation only
   for `free_surface_masked`; other fused zero-force requests remain rejected.

No additional resident field, particle pass, CG solve or host/device transfer is
introduced.

## Qualification matrix

The supplied smoke/qualification runner uses the same two-phase liquid/gas
state family and activates the full current Q6-g-f stack: x6c/x6f2, x6f,
x6g EOS pressure, A+B1 and x7d with `tau_rho=0.25`.  Resampling, virial and
Darcy are off so the test isolates boundary generalisation.

By default it runs:

```text
periodic_zero_force
channel_wall_zero_force
closed_box_zero_force
closed_box_gravity
io_fullface_x
io_fullface_y
io_segmented_lr
io_segmented_sameface
```

The open-boundary cases with zero body acceleration exercise the new
zero-force pre-transport semantic explicitly.  The same-face segmented case is
included to verify that x7f follows an existing structural 0264/0409
combination instead of hard-coding only the historical left/right layout.

Run after rebuilding:

```bash
LIVE_PROGRESS=1 bash scripts/run_0493x7f_q6_g_f_multibc_validation.sh
```

A smaller selected matrix can be run with, for example,

```bash
CASES="closed_box_zero_force io_fullface_x io_segmented_sameface" \
LIVE_PROGRESS=1 bash scripts/run_0493x7f_q6_g_f_multibc_validation.sh
```

The checker requires for each completed case:

- the expected resident Q6 boundary family;
- no species-Q6 CPU fallback or full-state download;
- a converged projected liquid solve and zero direct Q6 correction of the gas;
- active x7d time-based density restoration;
- represented x6f interface faces with no uncovered/truncated interface;
- active x6g EOS interface pressure on the same physical interface;
- finite Q6 timing diagnostics.

For closed and periodic cases the test remains a local operator qualification;
for open cases it does not demand constant liquid mass because inlet/outlet
transport is physical.  Long validation cases should instead close the liquid
mass balance against integrated inlet/outlet flux.

The checker writes

```text
runs/0493x7f_q6_g_f_multibc/q6_g_f_multibc_0493x7f.csv
```

including `totalSeconds`, `solveSeconds`, `applySeconds` and wall-clock time so
that later demonstration runs can quantify the performance cost of Q6-g-f.
