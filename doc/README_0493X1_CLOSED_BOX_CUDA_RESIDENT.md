# 0493x1 — static closed-box CUDA-resident boundary path

## Objective

`0493x1` extends the validated wall-channel resident path to a rigid rectangular
box with non-periodic boundaries in both directions. The immediate target is
the two-species dam-break demonstration, where the former segmented gas vent
introduced continuous gas insertion and an artificial falling plume.

The extension is opt-in:

```text
MPCD_CUDA_WALL_SIMPLE_CLOSED_BOX_0493X1=1
```

Legacy periodic and periodic-x wall-channel selections remain unchanged.

## First supported subset

The first closed-box subset is intentionally narrow:

- static full-domain rectangle;
- all four faces are `solid` or `specular`;
- no `bounceback` face;
- no open-boundary segment;
- no immersed solid;
- no moving or truncated fluid domain;
- no closed-capacity response;
- no resampling in the dam-break qualification.

The exclusion of bounceback avoids an unqualified order dependence when a
particle crosses two differently oriented bounceback faces during one time
step. Solid and specular faces use a normal reflection during streaming; a face
declared `solid` additionally receives the existing virtual-particle collision
coupling.

## CUDA data path

The resident sequence is:

```text
four-face force/stream/reflection 0246
  -> shared cell deposit and persistent SRC collision 0253
  -> independent-masked Q6 0400/0402 when requested
  -> resident Q6 thermostat 0400 or persistent SRC thermostat
```

The streaming kernel now supports either periodic wrapping in x or repeated
reflection between `xMin` and `xMax`. It already reflected between the lower and
upper y walls. Scalar diagnostics now include left/right hits and the maximum
number of x reflections in one step.

The persistent collision workspace already carried four per-face wall-enable
flags and four wall velocities. `0493x1` therefore only extends its topology
guard; the device virtual-particle implementation itself is reused unchanged.

The independent-masked Q6 operator already represented a non-periodic physical
face by zero normal base flux and a Neumann correction stencil. Its resident
support and audit guards now accept the closed-box topology and report:

```text
boundaryFamily = closed_box
openBoundaryEnabled = 0
```

## Dam-break wall choice

The updated `0493x0` runner uses:

```text
left   = specular
right  = specular
bottom = solid
top    = specular
```

This removes the lateral no-slip trail while retaining bottom-wall coupling and
closing the gas volume without a reservoir or outlet.

## Qualification

Build the live-visualization CUDA binary, then run the compact matrix:

```bash
LIVE_PROGRESS=1 bash scripts/run_0493x1_closed_box_smoke.sh
```

The smoke runs `src` and `src-q6` from the same two-species state. The shared
post-check requires:

- full requested step count;
- four closed wall parameters and no open-boundary segment;
- exact final particle count for each species;
- unchanged separate liquid and gas masses;
- zero inlet/outlet mutation counters at every sampled summary;
- for Q6, `boundaryFamily=closed_box`, resident execution without CPU fallback,
  converged liquid correction and zero direct gas correction.

The production-size qualitative run remains:

```bash
LIVE_PROGRESS=1 bash scripts/run_0493x0_dam_break_demo.sh
```
