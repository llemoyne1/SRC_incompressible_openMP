# SRC/MPCD C++ incompressible OpenMP

This repository contains a compact C++/OpenMP SRC/MPCD solver used to develop
and validate quasi-incompressible extensions of the classical compressible
SRC/MPCD method.

The current working branch is `feature/inlet-outlet`.  It keeps the classical
compressible mode available while adding Q6 velocity projection, Q9 mass-flux
projection and optional virial/EOS closure on top of the same generic finite-
volume elliptic projection core.

## Current branch status: `feature/inlet-outlet`

Validated in this branch:

- classical compressible SRC/MPCD still runs through `method = classic`;
- Q6 projection uses the generic elliptic operator for velocity/flux correction;
- Q9 mass-flux projection uses the same generic elliptic machinery and the
  elliptic low-pass filter path, with no case-specific FFT solver added;
- optional virial/liquid closure can be combined with Q9 as `method = q9_virial`;
- full inlet/outlet open-channel configurations are validated for channels
  without immersed solids;
- particle inlet ramping is applied consistently to the particle inlet, Q6 open
  flux and Q9 open mass flux;
- full-height inlet/outlet has been validated with both slip/specular walls and
  VP/no-slip solid thermal walls;
- segmented inlet/outlet apertures exist and should be treated as physical
  slit/nozzle geometries, not as a correction for the canonical Poiseuille
  channel.

Out of scope for the validated inlet/outlet closure:

- Q9/virial behavior in cells adjacent to immersed solids;
- backward-step/obstacle/cylinder runs with Q9/virial active next to the solid;
- any workaround based on trimming the Poiseuille inlet/outlet aperture to hide
  wall-corner artifacts.

Those immersed-solid issues should be developed separately, for example on a
branch such as `feature/q9-immersed-solid-boundary`, using a face/cell mask in
which fluid cells adjacent to the solid remain active and the solid-normal flux
is closed.

## Build

```bash
./scripts/build_src_mpcd_base.sh
```

The main executable is written to:

```text
build/src_mpcd_base
```

A small elliptic-core validation executable is also built:

```text
build/validate_elliptic_projection
```

Run it with:

```bash
./build/validate_elliptic_projection
```

## Running the solver

The solver is parameter-file driven:

```bash
./build/src_mpcd_base examples/params_periodic_base.kv
./build/src_mpcd_base examples/params_channel_y_bounceback.kv
```

Most examples require an `.smpcd` initial state.  MATLAB helpers in `matlab/`
can generate and inspect those binary particle-state files.  Typical workflow:

```matlab
addpath('matlab')
% Generate the state required by the chosen parameter file, then run from bash.
```

Useful runtime controls include:

```text
method = classic | q6 | q9 | q9_virial
projectionOperator = elliptic_fv_cg
q9TargetFilter = elliptic_lowpass
numThreads = 4
summaryEvery = 100
dumpStateEvery = 5000
```

## Inlet/outlet nominal settings

For the validated full open-channel inlet/outlet cases, use full-height open
boundaries and keep Q9/virial active up to the open boundary:

```text
bcLeft = inlet
bcRight = outlet
bcBottom = solid
bcTop = solid

openBoundaryApertureEnable = false
q9OpenBoundaryExclusionCells = 0
virialOpenBoundaryExclusionCells = 0
```

The zero-exclusion setting is important.  Non-zero open-boundary exclusions were
found to create an artificial active/inactive interface near the outlet, which
behaves like a numerical wall or impedance layer.

The nominal Q9 correction limiter is thermal-soft:

```text
q9CorrectionLimiterMode = thermal_soft
q9CorrectionVelocityLimiterOverThermal = 0.5
q9CorrectionLimiterThermalKBT = 0.0
```

For `kBT = 0.0025`, this gives:

```text
dU_limit = 0.5 * sqrt(kBT) = 0.025
```

The nominal low-mass policy is gamma-relative:

```text
q9LowMassTreatment = ramp_floor
q9LowMassRampStartOverGamma = 0.05
q9LowMassRampEndOverGamma = 0.40
q9MassFloorForCorrectionOverGamma = 0.40
q9MinCellMassForCorrectionOverGamma = 0.40
```

Keep the inlet velocity ramp enabled for long runs unless deliberately running a
start-up shock/stress test:

```text
inletVelocityRampEnable = true
inletVelocityRampStartTime = 0.0
inletVelocityRampEndTime = 20.0   # or longer for production runs
inletVelocityRampInitialFactor = 0.0
inletVelocityRampFinalFactor = 1.0
inletVelocityRampProfile = smoothstep
```

The ramp factor is used coherently by the particle inlet, Q6 open-boundary flux
and Q9 open-boundary mass flux.

## Recommended inlet/outlet scripts

Validated or nominal full-channel scripts:

```bash
# Full inlet/outlet, slip/specular wall baseline.
./scripts/run_open_channel_full_io_q9_virial_excl0_0087.sh

# Full inlet/outlet, VP/no-slip walls, Poiseuille mean profile.
./scripts/run_open_channel_full_io_vp_poiseuille_q9_virial_excl0_0088.sh

# Full inlet/outlet, VP/no-slip walls, tapered-flat mean profile.
./scripts/run_open_channel_full_io_vp_tapered_flat_q9_virial_excl0_0089.sh
```

Physical segmented aperture / slit-nozzle prototype:

```bash
./scripts/run_open_channel_jet.sh
```

The segmented-aperture script is intentionally not a canonical Poiseuille
validation.  It represents a physical slit/nozzle configuration with distinct
left/right open apertures.

Legacy/stress-test script:

```bash
./scripts/run_poiseuille_segmented_inlet_outlet_softlimited_q9_0083.sh
```

This keeps the early segmented aperture experiment available, but it should not
be used to claim canonical Poiseuille validation.

## MATLAB post-processing

MATLAB helpers in `matlab/` provide run summaries, field reconstruction and
visual checks.  Launch MATLAB from the repository root or from `matlab/` as
required by each script.  For the recent inlet/outlet runs, the common analysis
entry point is:

```matlab
cd matlab
R = analyze_poiseuille_hard_inlet_free_outlet_0077( ...
    'root','..', ...
    'runRoot','../runs/<run-root>', ...
    'caseGlob','openchan_*');
```

The useful fields for visual inspection include `rho`, `N`, `Ux`, `Uy`, `speed`,
`omega`, `particles` and wall-band diagnostics where available.

## Documentation map

Older branch-level documentation is in `docs/`.  Newer development notes from
the inlet/outlet validation campaign are in `doc/`.

Current key notes:

- `doc/README_0090_INLET_OUTLET_VALIDATION_STATUS.md`: final validation status
  of full inlet/outlet channel cases;
- `doc/README_0091_INLET_OUTLET_ROOT_CLEANUP.md`: root README/script cleanup and
  slit/nozzle separation;
- `doc/NEXT_CHAT_PROMPT_0091_SEGMENTED_INLET_OUTLET.md`: continuation prompt for
  developing physical segmented inlet/outlet cases.

Core method documents remain in `docs/`:

- `docs/ELLIPTIC_PROJECTION_CORE.md`;
- `docs/Q6_PERIODIC_ADAPTER.md`;
- `docs/Q6_CHANNEL_POISEUILLE_VALIDATION.md`;
- `docs/Q9_PERIODIC_ADAPTER.md`;
- `docs/POISEUILLE_Q9_FILTERED_CHANNEL_VALIDATION.md`;
- `docs/VIRIAL_EOS_PISTON.md`;
- `docs/IMMERSED_SOLID_Q6_Q9_MASK.md`.

## Repository hygiene

Generated files should not be committed:

```text
build/
runs/
outputs/
*.smpcd
*.zip
*.patch
*Zone.Identifier
```

No `.patch` files should be produced for future handoffs.  Use differential
archives named `*_files_only.zip` containing only modified or added files.
