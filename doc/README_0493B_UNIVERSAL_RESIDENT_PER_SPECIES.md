# 0493b — Universal resident runtime and per-species resampling

Base required:

```text
branch: surf
commit: aa0a4a0a42f3370f920ae2e1fa1bcb4939ec9140
```

## Purpose

0493b completes the 0493a routing change at runtime and adds an orthogonal
resampling switch to each registered species. Boundary conditions, immersed
solids, Darcy/Brinkman and Q6 remain physical producers/consumers of the same
resident particle state; none of them selects a different resampling backend.

## Configuration

The existing `speciesK` record is unchanged. The switch is a separate key:

```text
species0 = 1 solvent liquid 1.0 1.0 60
species0ResamplingEnable = true

species1 = 2 colloid dispersed 0.0 0.0 6
species1ResamplingEnable = false
```

The default is `true`. Existing configurations that omit the new key therefore
retain their historical behaviour.

`dispersed`, `colloid` and `colloidal` are accepted phase-family spellings for
registered dispersed species. This phase remains distinct from the liquid and
gas target-mass proxies.

## Mutation contract

All species remain present in the 0490h species-cell deposit and continue to
participate in streaming, SRC collision, boundary injection/extraction,
Darcy/Brinkman, thermostat, Q6 and barycentric momentum correction.

For a species whose switch is false, the resampling stages perform no:

- empty-cell refill;
- split or merge;
- donor/receiver transfer;
- species mass closure;
- mass or velocity restoration attributable to the species-aware resampling
  operations. The 0298 relative-energy restoration is restricted to enabled
  species and preserves the enabled-species momentum about its own cell mean.

The 0490k planner excludes disabled species from mutable donor/receiver mass.
The 0490m application and 0297 population guard independently check particle
types immediately before mutation. A forbidden attempt increments
`disabledSpeciesMutationCount` and is fatal.

## Universal resident runtime

The residual periodic/no-solid guards are removed from 0490m, 0490n and the
parameter validator. Cell indexing in 0490m wraps periodic axes and clamps
bounded axes. 0490n builds its physical-fluid mask on the device for fixed or
moving circle/rectangle solids and consumes the current Darcy `chi` device
field when the resampling chi filter is enabled.

The CUDA particle state is authoritative in production. 0490m downloads only
fixed-size scalar diagnostics; it does not download operation arrays or patch
particle attributes back to the host. The resident 0297 population guard keeps
cell moments and kinetic-energy fields on the device, and 0490n builds its solid
cell policy on the device rather than reconstructing a host policy mirror.

## Physics deliberately unchanged

0493b does not modify:

- SRC equations, collision parameters or thermostat;
- Q6 kernels, Q6 strengths, species weighting or barycentric correction;
- boundary-condition kernels or inlet/outlet flux definitions;
- Darcy/Brinkman force kernels or the construction of `chi`;
- split/merge thresholds and mass-closure formulae when all species switches
  are true;
- the guard that suppresses generic 0296 reconditioning in the species-aware
  path.

## Validation supplied

`scripts/check_0493b_universal_species_resampling.sh` performs structural,
syntax and routing checks and runs all eight matrix cases in preflight mode.

`scripts/run_0493b_universal_species_resampling_matrix.sh` compiles once, then
runs short cases for:

1. periodic, both species enabled;
2. periodic, solvent enabled and colloid disabled;
3. walls;
4. full-face inlet/outlet;
5. segmented inlet/outlet;
6. Darcy;
7. segmented inlet/outlet plus Darcy;
8. Q6 multi-species plus segmented inlet/outlet plus resampling.

Use `LIVE_PROGRESS=1`. The matrix runner uses the root
`livevis_control.kv` only when LiveVis is explicitly enabled and never
overwrites it by default.

## Expected commands after application

```bash
bash scripts/check_0493b_universal_species_resampling.sh
bash scripts/build_src_mpcd_cuda_q6_resident_livevis_0486.sh
LIVE_PROGRESS=1 bash scripts/run_0493b_universal_species_resampling_matrix.sh
```

The package checker is static/preflight validation. A real NVCC build and GPU
matrix run remain required on the project workstation.
