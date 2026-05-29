# 0110 — OpenMP resampling baseline: minimal SRC + Q6 core

## Goal

This patch reduces the active OpenMP executable to the minimal core needed for
porting the MATLAB weighted-resampling method.  The active branch keeps:

- classical SRC/MPCD (`method = classic`);
- Q6 velocity projection (`method = q6` or `projectionEnable = true`);
- particle boundary conditions, including periodic, solid walls and inlet/outlet;
- wall virtual particles used by the SRC collision step;
- analytic immersed solids and Q6 immersed-solid projection masks;
- mass-aware cell thermostat;
- `.smpcd` state I/O and runtime summaries.

It deliberately removes Q9 mass-flux projection and virial/EOS pressure-kick
modules from the active executable.  This prepares a clean insertion point for
weighted resampling without the former Q9/virial liquid-closure paths.

## Files modified

```text
README.md
include/simulation_params.h
include/src_mpcd_base.h
include/runtime_summary.h
src/params_io_base.cpp
src/src_mpcd_base.cpp
src/main_src_mpcd_base.cpp
src/runtime_summary.cpp
scripts/build_src_mpcd_base.sh
```

## File added

```text
scripts/run_resampling_minimal_src_q6_smoke_0110.sh
```

## Files to remove from this branch

The archive cannot delete files by itself.  After applying the archive, remove
the inactive Q9/virial implementation files from Git:

```bash
git rm include/q9_projection_adapter.h src/q9_projection_adapter.cpp
git rm include/virial_pressure_kick.h src/virial_pressure_kick.cpp
```

The generic elliptic projection core remains present and active because Q6 uses
it directly.

## Active solver sequence after reduction

```text
body acceleration
streaming
particle boundary conditions
immersed-solid reflection
SRC collision with wall/immersed virtual-particle contributions
Q6 velocity projection when requested
cell-relative thermostat when requested
optional keepMeanFlow correction
runtime summary / dump
```

There is no active Q9 mass-flux projection and no active virial/EOS kick.

## Parser policy

Accepted methods are now only:

```text
method = classic
method = q6
```

Unsupported method values are rejected explicitly.  Parameter keys beginning
with `q9`, `virial`, `massFlux` or `lowK`, and the aliases `Kvirial` and
`betaEOS`, are rejected with a clear message.  This prevents accidental reuse of
old Q9/virial parameter files on the resampling baseline.

## Runtime summary change

`summary_runtime.csv` no longer contains `q9*` or `virial*` columns.  It keeps:

- global mass/momentum/temperature diagnostics;
- particle boundary diagnostics;
- wall/immersed virtual-particle collision diagnostics;
- thermostat diagnostics;
- Q6 diagnostics, including immersed-solid closed-face and leak metrics;
- Q6 open-boundary flux diagnostics.

Post-processing scripts that expect Q9 or virial columns should not be used on
this branch without adaptation.

## Validation commands

Build and elliptic-core validation:

```bash
./scripts/build_src_mpcd_base.sh
./build/validate_elliptic_projection
```

Self-contained periodic SRC/Q6 smoke:

```bash
./scripts/run_resampling_minimal_src_q6_smoke_0110.sh
```

Expected behavior:

```text
build succeeds without compiling q9_projection_adapter.cpp or virial_pressure_kick.cpp
validate_elliptic_projection converges at roundoff-level residuals
classic smoke completes
q6 smoke completes
q6DivAfterProjectedFluxRms is small and finite
summary_runtime.csv contains no q9* or virial* columns
```

Unsupported Q9 check:

```bash
cat > /tmp/q9_reject.kv <<'KV'
inputState = runs/resampling_minimal_src_q6_smoke_0110/initial_32x32_g4.smpcd
outputDir = runs/q9_reject
Lx = 1
Ly = 1
Nx = 32
Ny = 32
dt = 0.001
nSteps = 1
method = q9
summaryEvery = 1
KV
./build/src_mpcd_base /tmp/q9_reject.kv
```

Expected result:

```text
Fatal error: method currently accepts: classic, q6
```

## Next patch recommended

The next patch should not yet implement extraction/insertion.  It should add the
formal particle-role/resampling scaffolding:

```text
ParticleRole: Inactive / Fluid / Latent
ParticleState::role, backward-compatible with absent role => Fluid
RealFluidWeightedDeposit excluding wallVP and immersedVP
resampling diagnostics: MRelRMS, mParticleRelStd, mMin, mMax, N/M per cell
```

This keeps the existing `type` field free for future physical species or
multi-population fluids.
