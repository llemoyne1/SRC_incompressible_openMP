# GPU patch 0291 — explicit CUDA outlet regimes

This patch extends the CUDA resident SRC classic inlet/outlet path with explicit outlet regimes while keeping the liquid closure modules (Q6, resampling and virial/capacity) disabled in the fast path.

The SRC classic definition used here is:

```text
advection / streaming
+ random grid shift
+ SRC rotation / collision
+ thermostat
```

## New outlet modes

The existing key `openBoundaryOutletMode` is extended for the particle-level CUDA inlet/outlet path:

```text
openBoundaryOutletMode = neumann
openBoundaryOutletMode = equilibrium_flux
openBoundaryOutletMode = forced_flux
```

### `neumann`

Passive outlet. Particles are deleted only when they naturally cross an outlet boundary/segment. No extra extraction is applied. This is appropriate for open-channel cases where the interior flow carries particles to the outlet.

Aliases already accepted by the parser, such as `free`, `zero_gradient` and `zero_normal_gradient`, remain passive.

### `equilibrium_flux`

After natural outlet deletion and hard-inlet reservoir insertion, the CUDA path estimates the current net particle gain of the open-boundary step and deletes additional particles from the outlet layer to cancel that gain.

This mode is convenient for long demonstrations with approximately constant particle inventory, but it is deliberately coupled to the inlet flux.

### `forced_flux`

Extra particles are deleted from the outlet layer according to a user-prescribed flux, independently of the inlet flux. This is intended for suction, drainage or cavity-aspiration configurations where the user wants to control inflow and outflow separately.

New parameters:

```text
openBoundaryOutletForcedMassFlux = 0.0          # mass per unit time; per-step target = flux*dt
openBoundaryOutletForcedMassPerStep = 0.0       # direct mass-per-step override
openBoundaryOutletForcedParticleFlux = 0.0      # particles per unit time; per-step target = flux*dt
openBoundaryOutletForcedParticlesPerStep = 0    # direct particle-count-per-step override
openBoundaryOutletForcedLayerCells = 1          # outlet extraction layer thickness
```

If both mass and particle targets are provided, the particle-count target takes priority. This first implementation keeps the algorithm simple and avoids new case-specific diagnostics.

## Reservoir exhaustion message

The former verbose overflow error:

```text
hard reservoir needs more inactive slots; GPU append is intentionally disabled...
```

is replaced by a clearer message of the form:

```text
cuda_classic_src_io_resident_0263: Reservoir exhausted at step <step> in segmented hard inlet reservoir; GPU append is disabled. Increase inactive slots or reduce the net injected flux. Details: ...
```

The detailed counters are kept after the concise explanation.

## Demonstration usage

The same-face U-flow demo now exposes the outlet regime through environment variables. Passive behaviour remains the default:

```bash
OUTLET_MODE=neumann \
BIN=build/src_mpcd_base_cuda_0291 \
bash scripts/run_demo_src_classic_cuda_box_same_face_io_0283.sh
```

A forced suction/extraction run can be launched for example with:

```bash
OUTLET_MODE=forced_flux \
OUTLET_FORCED_PARTICLES_PER_STEP=20 \
OUTLET_FORCED_LAYER_CELLS=3 \
BIN=build/src_mpcd_base_cuda_0291 \
bash scripts/run_demo_src_classic_cuda_box_same_face_io_0283.sh
```

The user is responsible for balancing inlet and outlet fluxes if a constant global mass is desired. Unbalanced fluxes are now intentional and can be used to study suction or pressurisation.

## Scope

This patch affects only the CUDA resident SRC classic inlet/outlet path. It does not migrate or alter Q6, resampling, virial/capacity pressure closure, or the future Q6 CUDA chantier.
