# 0493x9h — `phaseInterfaceBSelector=wall`: passive resident wall geometry provider

Incremental patch **on top of the validated 0493x9g phase-pair generalization**.

## Purpose

x9h activates the selector

```text
phaseInterfaceBSelector = wall
```

without deciding that a "solid" must be implemented by one particular kinetic
boundary condition.  The wall side is represented by a common resident geometry
contract, independent of whether the source is an external static wall or an
immersed chi field.

This patch is intentionally **geometry-only**.  It does **not** yet impose a
contact angle, a liquid/solid Laplace jump or a new Q6 wall pressure condition.
That separation prevents the already-qualified free-surface capillarity from
being altered while the wall geometry is being qualified.

## Geometry provider

The resident wall scalar is

```text
S = solidFraction in [0,1]
```

with wall normal oriented from fluid/phase A toward solid/phase B.

x9h automatically composes two existing geometry sources:

1. **Static domain walls** — any face using `solid`, `specular` or `bounceback`.
   The first fluid cell is not relabelled as solid.  Instead, x9h uses exact
   `S=1` ghost samples behind the wall face.  This keeps wall location at the
   physical domain face and makes the geometry independent of the particle
   reflection/accommodation mechanism.

2. **Darcy/chi wall geometry** — accepted only when
   `darcyBrinkmanEnable=true` **and** `darcyChiCollisionVpEnable=true`.
   This is deliberate: not every Darcy/porous chi field is automatically
   reinterpreted as a material wall.  The existing chi-collision wallVP opt-in
   is reused as the declaration that the chi field is wall geometry.

The repository convention is

```text
chi = 1  fluid
chi = 0  solid
```

so x9h stores

```text
S = 1 - chi.
```

If domain walls and chi-wallVP are both present, their geometry is naturally
combined: interior `S` comes from chi and off-domain wall ghosts remain solid.
No new runtime parameter is introduced.

## Resident fields

x9h adds lazily allocated CUDA fields only when `B=wall`:

```text
phaseWallFraction0493x9h
phaseWallNormalX0493x9h
phaseWallNormalY0493x9h
```

The normal uses the same rotationally improved 3x3 Scharr stencil family as the
qualified x9b/x9c curvature work.  For domain walls the Scharr samples query the
exact solid ghost geometry; for chi walls they query `1-chi`.

These fields are **separate from `alpha_x6c` and from p3 curvature alpha**.
Therefore x9h does not move the free surface and cannot change the x9d capillary
trajectory merely by making wall geometry available.

## Deliberate physics gates

For `phaseInterfaceBSelector=wall`, x9h does **not** register the wall as the
alpha-low x6f pressure/Dirichlet side.  Existing Q6 wall boundary conditions stay
authoritative.

Until the wall/contact-angle closure is developed, x9h rejects:

```text
surfaceTensionSigma > 0 with B=wall
x7b virial-density closure with B=wall
x7d density relaxation with B=wall
```

The x6g gas-pressure provider is not applied to a wall side because a wall has no
particle EOS pressure in this patch.

This is intentional.  A contact line is a three-medium problem (fluid A,
exterior fluid and solid), so x9h should supply geometry first rather than
silently inventing a liquid/solid pressure jump.

## Audit

On the normal Q6-G-F summary cadence, x9h writes

```text
output/cuda_wall_geometry_0493x9h.csv
```

including:

- which domain faces supply wall geometry;
- whether a chi-wallVP provider is active;
- number of interior solid and mixed cells;
- one-cell/Scharr wall-band size;
- number/fraction of cells with a valid wall normal;
- mean solid fraction;
- RMS unit-normal error.

The existing x9g

```text
output/cuda_phase_pair_0493x9g.csv
```

also records `B=wall`, with `phaseInterfaceEnabled=0` and
`phaseBPressureEnabled=0` in x9h.

## Validation runner

`run_0493x9h_wall_geometry_provider.sh` executes two short, fully occupied liquid
cases with `surfaceTensionSigma=0` and density closure disabled:

### `domain_wall`

- closed box;
- four specular boundary faces;
- no Darcy field;
- expected resident solid fraction inside the grid: zero;
- expected wall band: exactly the one-cell perimeter;
- normals supplied entirely by solid ghost samples.

### `chi_wall`

- periodic box;
- binary circular chi field;
- zero Brinkman penalty (`darcyAlphaMax=0`) and zero wallVP strength so the test
  remains a geometry qualification;
- `darcyChiCollisionVpEnable=true` declares chi as wall geometry;
- expected `S=1-chi`, nonzero circular wall band and valid normals.

The analyzer checks both the x9g pair contract and the x9h geometry invariants.

## Apply

From repository root after extracting the bundle:

```bash
python3 x9h_bundle/tools/apply_0493x9h_wall_geometry_provider.py

git diff --check -- . ':(exclude)livevis_control.kv'

bash -n scripts/run_0493x9h_wall_geometry_provider.sh
python3 -m py_compile scripts/analyze_0493x9h_wall_geometry_provider.py

g++ -std=c++17 -Iinclude -fsyntax-only src/params_io_base.cpp

bash scripts/build_src_mpcd_cuda_q6_resident_livevis_0486.sh
```

The apply script is idempotent and uses targeted semantic anchors; it does not
require a clean Git working tree.

## Preflight

```bash
PREFLIGHT_ONLY=1 LIVE_VIS_ENABLE=0 LIVE_PROGRESS=1 \
bash scripts/run_0493x9h_wall_geometry_provider.sh
```

## Runtime validation

```bash
LIVE_VIS_ENABLE=1 LIVE_VIS_HOLD_ON_EXIT=0 LIVE_PROGRESS=1 \
FILTERED_RECORDING_ENABLE=0 \
bash scripts/run_0493x9h_wall_geometry_provider.sh
```

Expected final line:

```text
[0493x9h-check] status=PASS
```

## What x9h does not claim

x9h does **not** yet claim:

- prescribed contact angle;
- liquid/gas/solid triple-line closure;
- liquid/solid capillary pressure;
- wall-aware modification of p3 free-surface curvature;
- general identification of every Darcy/porous field as a solid.

The next wall patch can consume the resident `S` and wall-normal fields to impose
an explicit contact-angle condition on the **curvature-only** interface geometry,
without changing `alpha_x6c` or the qualified bulk Q6-G-F machinery.
