# 0493g — species-local population-guard moment restoration

## Purpose

0493f-fix2 demonstrated that the type-preserving population-guard split/merge
operations conserve cell mass and mixture momentum/energy, but the subsequent
0298 energy restoration exchanges momentum and thermal energy between two
simultaneously enabled species.

0493g changes only that post-mutation restoration:

- target and current relative kinetic energy are accumulated for every
  `(species, cell)` pair;
- each enabled species is rescaled around its own cell barycentric velocity;
- mass, momentum and relative kinetic energy are therefore closed separately
  for every enabled species;
- resampling-disabled species are untouched;
- the historical mixture restoration remains the fallback when no valid
  species device view exists.

No selection, split/merge, 0490k/0490m transfer, Q6, Darcy, boundary-condition,
thermostat or CPU path is changed.

## Validation correction

The new 0493g analyzer also removes two false population-count failures:

- with two enabled species, one guard pass may correct only one type because the
  guard applies at most one split or merge per cell; exact `5/5` is required at
  the short-run endpoint, not necessarily after the first pass;
- with one enabled species, the enabled type must become the cellwise complement
  of the disabled `4/6` checkerboard, rather than remain uniformly `5/5`.

The physical checks remain blocking: local and global mass, momentum and energy
must be invariant both for the mixture and for each species.

## Files

Modified:

- `src/cuda_resampling_population_guard_0297.cu`

Added:

- `scripts/run_0493g_two_species_moment_restore.sh`
- `scripts/analyze_0493g_two_species_moment_restore.py`
- `README_0493G_SPECIES_LOCAL_MOMENT_RESTORE.md`

## Install

From the repository root:

```bash
python3 /path/to/SRC_GPU_SURF_PATCH_0493G_SPECIES_LOCAL_MOMENT_RESTORE/apply_patch_0493g.py .
```

The installer accepts the exact expected pre-patch source SHA-256 and refuses to
overwrite modified targets. It creates a rollback backup under
`.git/patch_backups/0493g_<timestamp>/`.

## Rebuild

A rebuild is required:

```bash
bash scripts/build_src_mpcd_cuda_q6_resident_livevis_0486.sh
```

## Test

```bash
LIVE_PROGRESS=1 \
bash scripts/run_0493g_two_species_moment_restore.sh
```

The decisive checks are:

- `both_*_type1_momentum` and `both_*_type2_momentum`;
- `both_*_type1_thermal_energy` and `both_*_type2_thermal_energy`;
- the corresponding cell-field checks;
- exact `5/5` composition at the short endpoint;
- complementary active/disabled counts in the one-species-active cases;
- zero 0490k plan entries and zero 0490m direct operations for this physically
  neutral state.

## Generation-time validation

Performed without a CUDA GPU/compiler:

- Python analyzer compilation: PASS;
- shell syntax: PASS;
- synthetic five-case analyzer campaign: PASS;
- species-local restoration algebra test: PASS;
- Clang CUDA host-side syntax check of the added kernels/helper with stubs: PASS;
- static contract checks: PASS;
- installer idempotence and rollback tests: PASS.

A real NVCC build and CUDA run are intentionally left to the target workstation.
