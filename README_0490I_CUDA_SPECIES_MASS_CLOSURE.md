# 0490i — Resident CUDA species-aware mass closure

## Scope

0490i ports the phase/species-aware mass closure introduced in 0490d to the
resident CUDA particle state. It consumes the resident 0490h species-cell
workspace and applies the local particle-mass scaling on device.

The patch is opt-in:

```text
speciesResamplingMassClosureEnable = true
speciesResamplingMassClosureCudaEnable = true
```

Legacy trajectories are unchanged when the CUDA option is disabled.

## Cell policy

For species `s` in cell `c`, 0490h provides `M_{c,s}`. With the declared
reference cell mass `Mref_s`, define the occupancy proxy

```text
W_c = sum_s M_{c,s}/Mref_s
```

and the local target mass

```text
Mtarget_c = M_c/W_c.
```

The declared closure strength `beta_s` is mixed with the same occupancy proxy:

```text
betaSpecies_c = sum_s [(M_{c,s}/Mref_s) beta_s] / W_c
beta_c = clamp(betaGlobal betaSpecies_c, 0, 1).
```

The effective cell mass is

```text
Meffective_c = M_c + beta_c (Mtarget_c - M_c),
```

and every fluid particle in the cell receives the same factor

```text
m_i <- m_i Meffective_c/M_c.
```

Therefore the local species composition is preserved exactly, up to floating
point roundoff, and the CUDA rule is the same as the CPU 0490d rule.

## Resident implementation

`CudaSpeciesCellWorkspace0490h` remains allocated in `SrcMpcdBaseWorkspace`.
0490i adds `CudaSpeciesMassClosureWorkspace0490i`, containing resident arrays
for:

- declared species closure strengths;
- local target cell mass;
- local closure strength;
- mass scale;
- remap-cell flags;
- particle edit counter.

The execution order is:

```text
shared CUDA particle state
-> 0490h resident species deposit
-> 0490i target/strength kernel
-> 0490i particle mass scaling kernel
-> diagnostic cell-array download
-> active mass/velocity prefix download for the existing CPU post-deposit path
```

The shared CUDA state is marked fresh after the edit. The host download does not
make the operation CPU-authoritative; it only keeps the current post-remap CPU
diagnostics and summary path coherent until those consumers are also ported.

## Strict checks

0490i rejects:

- an unregistered fluid type;
- a CUDA/CPU pre-remap total-cell-mass mismatch above
  `speciesMassClosureCudaComparisonTolerance`;
- a closed-capacity target override;
- thermal renormalization in the same patch.

Thermal renormalization is deliberately deferred to a later resident CUDA
milestone. `resamplingMassGuardEnable` and closed-capacity response remain
excluded by the 0490d validation.

## Diagnostics

The default file is:

```text
cuda_species_mass_closure_0490i.csv
```

It records workspace reuse, shared-state reuse, edited cells/particles, scale
range, local target/strength ranges, mass before/after and kernel/upload/download
timings.

## Smoke test

```bash
LIVE_PROGRESS=1 \
BIN=build/src_mpcd_base_cuda_q6_resident_0490i \
bash scripts/run_0490i_cuda_species_mass_closure_smoke.sh
```

The test runs the same two-step case through the CPU 0490d path and the CUDA
0490i path. It checks:

- CPU/GPU species-cell equivalence;
- expected cell masses at both steps;
- separate global liquid and gas mass conservation;
- resident reuse of both the 0490h and 0490i workspaces;
- a fresh preserved shared CUDA particle state.
