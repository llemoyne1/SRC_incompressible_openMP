# 0491 - Species-sensitive Q6 contract and CUDA-resident apply

## Scope

0491a starts the Q6 multi-species work from the design note
`conception_q6_multiespeces_cuda_resident_0491.pdf`.

The scientific contract is intentionally narrow:

- keep one barycentric Q6 projection for the mixture;
- do not solve one pressure equation per species;
- use the existing `q6StrengthDeclared` species coefficient as a relative
  participation weight;
- preserve the barycentric Q6 correction exactly after recomposition;
- keep production trajectories unchanged unless `speciesQ6Enable=true`.

## Parameters

The minimal accepted keys are:

```text
speciesQ6Enable = false
speciesQ6Mode = common        # common | weighted
speciesQ6Sensitivity = 0.0    # eta in [0,1]
speciesQ6AlphaEpsilon = 1.0e-14
speciesQ6FallbackMode = common # common | fatal
speciesQ6ComparisonTolerance = 1.0e-11
```

No CUDA-specific species-Q6 flag is added. The existing
`projectionBackend=cuda` resident Q6 path is the only production implementation.

## Reference implementation

`include/q6_species_distribution_0491a.h` and
`src/q6_species_distribution_0491a.cpp` implement the deterministic cell-level
reference:

```text
alphaBar[c] = sum_s Y[c,s] alpha[s]
w[c,s] = (1 - eta) + eta alpha[s] / alphaBar[c]
du[c,s] = w[c,s] duQ6[c]
```

For every wet cell, the reference computes the recomposition residual:

```text
sum_s M[c,s] du[c,s] - M[c] duQ6[c]
```

This residual is the hard invariant for the later CUDA implementation.

## CUDA resident implementation

0491c replaces only the final 0400 particle correction application when
`speciesQ6Enable=true`. The barycentric deposit, elliptic solve, boundary
treatment, global momentum correction and divergence diagnostics remain the
resident Q6 reference.

The device path:

- reuses the resident CUDA particle state and the 0490h species-cell workspace;
- uploads only species `type` and `q6StrengthDeclared` metadata;
- deposits `M[c,s]` from the Q6 cell ids already computed on device;
- checks the barycentric recomposition residual against
  `speciesQ6ComparisonTolerance` before mutating particle velocities;
- applies `v_i += w[c,type_i] * duQ6[c]` in the particle correction kernel.

The CPU Q6 fallback still rejects `speciesQ6Enable=true`, because it has no
species-weighted apply path.

`summary_runtime.csv` reports this guard as
`q6SpeciesQ6BarycentricResidualMaxAbs`.

## Validation

Run:

```bash
bash scripts/run_0491a_species_q6_cpu_reference.sh
```

Covered analytic cases:

- one species with arbitrary alpha gives `w=1`;
- two species with equal alpha gives common Q6;
- two equal masses with alpha `(0, 1)` gives weights `(0, 2)`;
- a 25/75 mixture with alpha `(0.5, 1)` matches the hand calculation;
- pure neighboring cells keep `w=1`;
- all-zero alpha uses common fallback or throws in fatal mode.

Exit criterion for the CPU contract:

```text
[0491a] PASS species-Q6 CPU reference analytic smokes
```

## Injection smoke

`scripts/run_ok_injection_type1_into_type2_empty.sh` now defaults to
`speciesQ6Enable=true`, liquid type 1 with `q6Strength=1`, gas type 2 with
`q6Strength=0`, and a liquid/gas particle-mass ratio of 10. Because the case
contains pure gas cells with `alphaBar=0`, its default fallback is `common`;
set `SPECIES_Q6_FALLBACK_MODE=fatal` to audit that no wet cell lacks a
Q6-participating species.

## 0491d Path Matrix

`scripts/run_0491d_species_q6_path_matrix.sh` runs the liquid-into-gas case on
the four standard paths:

```text
src
src-resampling
src-q6
src-q6-resampling
```

The default small matrix uses `NX=8`, `NY=4`, `GAMMA=4`, `STEPS=1`. `GAMMA=4`
keeps the resampling population bounds strictly ordered in the resampling
paths.

The injection runner writes `speciesQ6Enable=false` for non-Q6 modes and keeps
`speciesQ6Enable=true` for Q6 modes. The summary script checks:

- exit code is zero and the expected step was reached;
- no fatal/stale/unsupported/CPU-fallback/non-finite marker appears in logs;
- Q6 modes use the resident Q6 flag and report `q6Applied=1`;
- non-Q6 modes keep `speciesQ6Enable=0`;
- Q6 species recomposition residual is finite and below
  `speciesQ6ComparisonTolerance`.

Outputs:

```text
runs/0491d_species_q6_path_matrix/species_q6_path_matrix_0491d.csv
runs/0491d_species_q6_path_matrix/species_q6_path_matrix_0491d.md
```

## 0491e Strict Resident Audit

`scripts/run_0491e_species_q6_strict_resident_audit.sh` isolates the
device-resident species-Q6 contract on a fully periodic two-species case. Each
cell is seeded with one liquid particle of mass 10 and three gas particles of
mass 1, so `speciesQ6Mode=weighted` exercises a non-trivial alpha weighting.

Run:

```bash
bash scripts/run_0491e_species_q6_strict_resident_audit.sh
```

The CUDA Q6 path writes `cuda_species_q6_0491.csv` when `speciesQ6Enable=true`.
The strict 0491e summary requires:

```text
species_q6_device_resident=1
species_q6_host_cell_array_entries=0
species_q6_weight_h2d=0
species_q6_full_state_download=0
species_q6_cpu_fallback=0
species_q6_remaining_cpu_scope=none
```

It also checks that resident Q6 strict flags were active, Q6 was applied, the
barycentric residual stayed below `speciesQ6ComparisonTolerance`, and logs do
not contain fatal/unsupported/CPU-fallback/non-finite markers.

Outputs:

```text
runs/0491e_species_q6_strict_resident/species_q6_strict_resident_0491e.csv
runs/0491e_species_q6_strict_resident/species_q6_strict_resident_0491e.md
runs/0491e_species_q6_strict_resident/output/cuda_species_q6_0491.csv
```

Current scope note: this strict resident smoke is periodic. The existing
0490m resident fast path rejects segmented inlet/outlet boundaries; liquid
injection through segmented boundaries is covered by 0491d for the Q6 species
contract and should be extended under the boundary/geometries milestone 0491g.

## 0491f Energy and Thermostat Validation

`scripts/run_0491f_species_q6_energy_validation.sh` validates the energy-facing
part of the species-Q6 contract on the same periodic two-species mass ratio
used by 0491e. It runs four short cases:

```text
common_no_thermostat
weighted_no_thermostat
common_thermostat
weighted_thermostat
```

The validation deliberately does not require common and weighted Q6 to have the
same kinetic energy without a thermostat: species-weighted correction can
redistribute particle-relative energy while preserving the barycentric Q6
correction. The checked invariants are instead:

- finite runtime energy/speed/mass summaries;
- zero mass drift within the configured tolerance;
- mass-weighted mean velocity remains near zero;
- Q6 is applied and the species barycentric residual remains below tolerance;
- thermostat cases are handled by the Q6 resident thermostat and reach the
  target `thermostatKBTAfter`;
- no fatal/unsupported/CPU-fallback/non-finite marker appears in logs.

The resident thermostat now reuses the particle `cellId` array already produced
by resident Q6. In the 0491f audit this is reported as
`thermostat_collision_cell_id_h2d_entries=0`.

Run:

```bash
bash scripts/run_0491f_species_q6_energy_validation.sh
```

Outputs:

```text
runs/0491f_species_q6_energy/species_q6_energy_0491f.csv
runs/0491f_species_q6_energy/species_q6_energy_0491f.md
runs/0491f_species_q6_energy/*/output/cuda_species_q6_energy_0491f.csv
```

Current scope note: `keepMeanFlowEnable=true` is still a CPU particle pass after
resident Q6 and therefore is not validated as a resident energy path in 0491f.
It should either gain a resident implementation or remain explicitly outside
strict resident runs.

## 0491g Boundaries and Darcy/Brinkman

`scripts/run_0491g_species_q6_boundary_darcy_matrix.sh` generalizes the
species-Q6 resident validation beyond the initial periodic box. The matrix runs
short weighted species-Q6 cases on:

```text
periodic
channel_wall
io_fullface
io_segmented_injection
darcy_channel
```

The Q6 projection itself remains barycentric and unchanged. The species
extension is still only the resident particle-correction apply:

```text
v_i += w[cell,type_i] * duQ6[cell]
```

The 0491g audit extends `cuda_species_q6_0491.csv` with:

```text
boundaryFamily,openBoundaryEnabled,darcyBrinkmanEnable
```

where `boundaryFamily` is one of `periodic`, `channel_wall`, `open_fullface`,
`open_segmented`, or `other`. The segmented injection case records liquid
injection as type 1 with the same mass ratio 10 used in the prior 0491 tests.
A compressible type 0 is also registered because legacy outlet segment records
carry a type field even when they do not inject particles.

Darcy/Brinkman keeps the existing physical placement after Q6/thermostat/mean
flow in the non-classic resident chain. Its CSV audit now records:

```text
speciesQ6Enable,q6ResidentInputFresh,particleUploadSkipped
```

The 0491g Darcy exit criterion is that `darcy_channel` consumes the fresh
resident particle state produced by species-Q6 and skips a redundant full
particle upload. The smoke also requires a non-trivial porous region
(`meanAlpha > 0`) so that the Brinkman kernel is actually exercised.

Run:

```bash
bash scripts/run_0491g_species_q6_boundary_darcy_matrix.sh
```

Outputs:

```text
runs/0491g_species_q6_boundary_darcy/species_q6_boundary_darcy_0491g.csv
runs/0491g_species_q6_boundary_darcy/species_q6_boundary_darcy_0491g.md
runs/0491g_species_q6_boundary_darcy/*/output/cuda_species_q6_0491.csv
runs/0491g_species_q6_boundary_darcy/darcy_channel/output/darcy_cost_0343.csv
```

Current scope note: immersed rectangle/circle geometries are still explicitly
outside strict resident species-Q6. The current resident Q6 guard rejects
`immersedSolidEnable` and projection masks, so these cases must not be reported
as CUDA-resident species-Q6 until that guard and the corresponding validation
are extended.

## 0491h Software Qualification and Performance

`scripts/run_0491h_species_q6_software_validation.sh` is the aggregate
qualification harness for the 0491 series. It does not add simulation
parameters. It reuses the staged smokes and consolidates their CSV audits.

Default run:

```bash
bash scripts/run_0491h_species_q6_software_validation.sh
```

The default `VALIDATION_PROFILE=software` is intentionally short. It validates
the harness, the software invariants, the boundary/Darcy coverage, a one-seed
four-path matrix, a persistent interface case and a trace-species case.

The full campaign requested by the design note is selected explicitly:

```bash
VALIDATION_PROFILE=full bash scripts/run_0491h_species_q6_software_validation.sh
```

In `full`, the runner requests:

```text
3 seeds x 1000 steps on src, src-resampling, src-q6, src-q6-resampling
10000 steps on SRC+Q6 weighted
10000 steps on SRC+resampling+Q6 weighted
```

The 0491h summary checks:

- all sub-stages exited cleanly;
- Q6 species residuals remain below `speciesQ6ComparisonTolerance`;
- no host cell-species array, weight H2D table, full-state download or CPU
  fallback appears in strict species-Q6 audits;
- no species workspace allocation occurs after the first audited step of a run;
- closed-domain species masses are conserved within tolerance;
- registered types remain registered and finite;
- persistent interface and trace-species cases are covered;
- performance counters are finite.

The Q6 species audit now includes:

```text
species_q6_allocated_bytes
species_q6_allocation_calls
species_q6_metadata_h2d_bytes
species_q6_deposit_seconds
species_q6_weight_seconds
species_q6_particle_apply_seconds
```

`species_q6_weight_seconds` is the resident recomposition/weight-validation
time. The final particle kernel still computes its weight locally, so the
reported `species_q6_particle_apply_seconds` is the measured cost of the actual
species-aware particle update.

Outputs:

```text
runs/0491h_species_q6_software_validation/species_q6_software_validation_0491h.csv
runs/0491h_species_q6_software_validation/species_q6_software_validation_0491h.md
```
