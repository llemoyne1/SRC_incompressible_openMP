# 0493x9g — phase-pair interface generalization

Incremental architectural patch **on top of 0493x9f**.

The purpose of x9g is to remove the production free-surface/capillary path's
hard-coded assumption that the interface is necessarily `Liquid/Gas`, while
preserving the already qualified x9d–x9f physics exactly for the legacy case.
It does **not** add new interfacial physics, change p3 curvature, change
`surfaceTensionSigma`, alter `phiGamma`, CG, B1, streaming, collision,
thermostat, or resampling.

## 1. Phase-pair contract

Two selectors are added to `SimulationParams`:

```text
phaseInterfaceASelector = family:liquid
phaseInterfaceBSelector = family:gas
```

Aliases accepted by the parser:

```text
capillaryPhaseASelector
capillaryPhaseBSelector
```

Phase A is the **alpha-high / projected side**.  Its selected particle species
provide the mass field used by the existing x6c alpha construction and its
reference cell mass provides the density scale used by the Laplace potential.

Phase B is the **alpha-low / exterior side**.  It determines whether an
alpha=0.5 crossing is a physical phase boundary and, when the x6g EOS pressure
provider is active, which registered species provide the exterior pressure.

The historical defaults are therefore exactly:

```text
A = family:liquid
B = family:gas
```

and are the intended no-physics-change compatibility path.

## 2. Selector grammar

Accepted forms are:

```text
family:liquid
family:gas
family:dispersed
family:unspecified

type:<uint32>

vacuum
wall
```

The short forms `liquid`, `gas`, `dispersed`, `unspecified` are canonicalized to
`family:*`; `none` is canonicalized to `vacuum`.

Constraints:

- A must resolve to one or more registered particle species with a positive
  total `referenceCellMassDeclared`.
- A and B may not overlap registered species.
- an explicit `type:*` B selector must match exactly one registered species;
- `B=vacuum` is operational and explicitly means that alpha=0.5 is a physical
  interface even without a registered B particle species;
- `B=wall` is **reserved by the public selector grammar but deliberately
  rejected in x9g**.  It is the hook for a later wallVP/contact-angle geometry
  adapter; x9g does not pretend that a wall alpha provider exists yet.

## 3. What is generalized in production

The resident x6c/x6f/x6g/x9d production chain is changed from implicit
Liquid/Gas semantics to A/B semantics:

```text
selected A particle masses
    -> raw alpha_A / referenceMass_A
    -> existing x6c filter
    -> existing alpha=0.5 x6f geometry/stencil
    -> existing p3 curvature
    -> existing sigma*kappa contribution to phiGamma
```

The projected x6f/x9d species must match phase A rather than the hard-coded
`SpeciesPhaseFamily::Liquid` test.

For the x6g EOS provider, the particle count used for exterior pressure comes
from phase B rather than from all `Gas` species.  The current EOS is still the
qualified ideal-gas provider, therefore if EOS mode is active all species
selected by B must still have `phaseFamily=Gas`.  A non-gas B is allowed only
when the B-pressure provider is constant/off; a general liquid-B pressure
solver is a later development.

A selector with no registered B species preserves the historical monophase
full-pressure-domain behaviour.  `vacuum` is distinct: it explicitly declares
an exterior phase and therefore activates the alpha=0.5 boundary topology.

## 4. What x9g deliberately does NOT claim

x9g is an **interface abstraction**, not yet a full symmetric immiscible
multiliquid solver.

In particular:

- B1 still requires exactly one projected Q6 species in the current resident
  implementation.
- x7c density relaxation and x7b virial retain their qualified one-Liquid
  constraints and are not generalized by x9g.
- x9g does not prevent two particle species from diffusing/mixing.  Therefore
  an arbitrary A/B pair does not by itself create immiscibility.
- a non-gas phase B does not yet have a second incompressible pressure solve
  coupled symmetrically to A.
- `wall` has no geometry/pressure adapter yet.
- the older standalone x6a pressure diagnostic and x6b geometry diagnostic
  retain their historical Liquid/Gas interpretation.  They are not the x6c/
  x6f/x6g production path and must not be used to claim arbitrary A/B support.

This separation is intentional: it lets the next wall or liquid/liquid work
attach a B-side provider without reopening the already qualified p3 + Laplace
coupling.

## 5. New audit

At geometry-audit steps x9g writes:

```text
output/cuda_phase_pair_0493x9g.csv
```

It records the canonical A/B selectors, selector kind/value, matched species
counts, A/B reference masses, whether B is entirely gaseous, whether an
exterior B boundary is present, whether B-pressure forcing is active, and
`surfaceTensionSigma`.

Historical workspace/audit field names containing `liquid` or `gas` are kept
where renaming them would create unnecessary churn; comments identify the new
A/B semantics in the production path.

## 6. x9f runner selectors

`run_0493x9f_ellipse_relaxation.sh` now accepts optional environment variables:

```text
PHASE_A_SELECTOR
PHASE_B_SELECTOR
```

If left empty the selector keys are not written at all, so the parser defaults
exercise the exact historical compatibility path.

Example explicit legacy-equivalent selection:

```bash
PHASE_A_SELECTOR=type:1 \
PHASE_B_SELECTOR=type:2 \
SIGMA=512 STEPS=20 LIVE_VIS_ENABLE=1 LIVE_PROGRESS=1 \
bash scripts/run_0493x9f_ellipse_relaxation.sh
```

## 7. Apply and build

From the repository root after extracting the bundle:

```bash
python3 x9g_bundle/tools/apply_0493x9g_phase_pair_generalization.py

git diff --check -- . ':(exclude)livevis_control.kv'

bash -n scripts/run_0493x9f_ellipse_relaxation.sh
bash -n scripts/run_0493x9g_phase_pair_equivalence.sh
python3 -m py_compile scripts/analyze_0493x9g_phase_pair_equivalence.py

bash scripts/build_src_mpcd_cuda_q6_resident_livevis_0486.sh
```

The apply script is semantic/context based, idempotent, has no working-tree
cleanliness guard, and handles being copied into `tools/` without a SameFile
failure.

## 8. Required equivalence qualification

Run:

```bash
LIVE_VIS_ENABLE=1 LIVE_PROGRESS=1 \
bash scripts/run_0493x9g_phase_pair_equivalence.sh
```

The suite runs the same x9f ellipse three ways:

1. **legacy** — no selector keys at all;
2. **family** — `family:liquid / family:gas` explicitly;
3. **type** — `type:1 / type:2` explicitly.

For the qualified one-liquid/one-gas state, the analyzer requires the physical
CSV outputs to be byte-for-byte identical between all three cases and verifies
the new phase-pair audit resolution.  Expected final line:

```text
[0493x9g-check] status=PASS
```

`LIVE_VIS_ENABLE=1` is the default for this suite; hold-on-exit is forced off
for the three-run sweep and filtered recording is forced off.

## 9. Validation performed while packaging

The semantic apply script was applied to a fresh reconstructed x9f source tree,
then applied a second time to verify idempotence.  The resulting modified
source files matched the intended x9g tree exactly.  The modified/new shell
runners pass `bash -n`, Python scripts pass `py_compile`, and
`src/params_io_base.cpp` passes a C++17 syntax-only compile.

CUDA/nvcc is not available in the packaging environment; the CUDA build and
runtime equivalence suite must therefore be executed on the project GPU host.
