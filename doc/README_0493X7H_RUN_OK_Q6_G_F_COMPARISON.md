# 0493x7h — run_ok three-way SRC / previous-Q6 / Q6-g-f comparison

## Objective

Use the previously successful `run_ok_*.sh` demonstrations as a physical-quality
regression campaign for the current Q6-g-f architecture.

Seven of the eight public historical entrypoints default to three paths:

```text
src
src-q6
src-q6-g-f
```

The current public injection wrapper is a deliberate exception when its phase
pair is `liquid/liquid`: Q6-g-f currently projects exactly one liquid carrier
species, so a two-liquid comparison would not be like-for-like.  In that
configuration the wrapper retains `src src-q6` by default and reports the reason.
A `liquid/gas` or `gas/liquid` injection pairing receives the full three-way
comparison without changing Q6-g-f semantics.

`src-q6` deliberately keeps the previous Q6 behavior.  `src-q6-g-f` is a new,
separate integration path and enables the qualified Q6-g-f stack without
silently changing the historical comparator.

The public entrypoints are:

- `run_ok_bend_pipe.sh`
- `run_ok_injection_type1_into_type2.sh`
- `run_ok_io_box_same_face.sh`
- `run_ok_naca.sh`
- `run_ok_poiseuille.sh`
- `run_ok_step.sh`
- `run_ok_tg.sh`
- `run_ok_vk.sh`

`run_ok_injection_type1_into_type2_empty.sh` remains the implementation backend
for the public injection runner and is updated so a phase-compatible wrapper can
select Q6-g-f safely.  An explicit `RUN_MODES=src-q6-g-f` with two projected
liquid species is rejected rather than silently changing the model.

A ninth public comparison case is added:

- `run_ok_dambreak.sh`

It is the production-sized dam-break used during Q6-g-f development, rewritten
with the same mode-loop/output layout as the other run_ok scripts.

## Meaning of the three modes

### `src`

Classic resident SRC/MPCD, projection disabled.  Existing boundary, Darcy,
thermostat and demo parameters are otherwise retained.

### `src-q6`

Historical Q6 path.  No x6f/x6g/x7d/B1 Q6-g-f opt-in is enabled.  This is the
control used to detect whether the new architecture improves or degrades a demo.
For the new dam-break runner it uses the earlier `independent_masked` two-species
Q6 with legacy force ordering.

### `src-q6-g-f`

Current Q6-g-f path:

```text
q6ForceProjectionMode = prestream_single_fused
speciesQ6Mode = free_surface_masked
q6DensityRelaxationTime = 0.25   # configurable
x6c geometry = on
x6f phase-interface stencil = on
A/B1 face-to-particle reconstruction = on
```

For true liquid/gas cases (a phase-compatible injection configuration and
dam-break), x6g is enabled in EOS mode using `p_ref = gamma*kBT/Acell`.
Single-phase historical demos use the monophase Q6-g-f limit and leave x6g off
rather than inventing a gas phase.  The historical liquid/liquid injection is
kept as an SRC / previous-Q6 regression until Q6-g-f is deliberately extended to
multiple projected liquid carriers.

## Darcy/chi comparison contract

The default campaign is first a **regression against the successful historical
demos**.  Therefore `src` and `src-q6` retain each runner's previous solid-domain
initialization and Darcy deactivation setting.

Q6-g-f + Darcy was qualified in 0493x7g with a filled fictitious Brinkman domain
and `darcyInitialDeactivateBelowChi < 0`.  Only `src-q6-g-f` therefore forces
particles to be generated in chi<1 and writes `darcyInitialDeactivateBelowChi=-1`.
This prevents the chi obstacle from being misread as a liquid/gas free surface.

For a complementary apples-to-apples **projection-isolation** experiment, set

```bash
RUN_OK_DARCY_COMMON_FILLED_STATE=1
```

Then all three modes use the same filled fictitious-domain state and disable
initial chi deactivation.  This second comparison is useful after the historical
regression because it removes the solid-initialization difference as a confounder.

## Dam-break defaults

The new `run_ok_dambreak.sh` uses the developed reference case:

```text
Lx x Ly       = 2 x 1
Nx x Ny       = 300 x 150
gamma         = 10
dt            = 0.005
kBT           = 0.05
gravityY      = -0.5
liquid column = 0.5 x 0.8
liquid mass   = 1000
gas mass      = 1
seed          = 493953
steps         = 5000
```

All three paths are generated from the same two-species state and seed.

## Compatibility

The legacy resampling integration modes remain accepted by the common helper and
can still be selected explicitly with `RUN_MODES`.  They are simply no longer in
the default `run_ok` physical-comparison campaign.

0493x7h changes scripts only; no CUDA kernel, Q6 equation, Darcy equation,
thermostat or resampling rule is modified.
