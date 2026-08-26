# 0490m — CUDA species-resident fast path and long validation

## Purpose

0490l validated the strict CUDA species resampling chain, but the accepted
0490k plan was still mirrored through host vectors before particle mutation:

1. download the compact transfer plan;
2. rebuild passive operations on CUDA and download them;
3. upload/consume those operations through the transitional 0448 backend;
4. retain full-state rollback and comparison machinery used by validation.

0490m introduces a production fast path that consumes the authoritative 0490k
device plan directly and applies the species-constrained donor/receiver edits to
the shared resident particle state.

## New production mode

Set:

```text
speciesResamplingCudaResidentFastPathEnable = true
speciesCudaResidentFastPathDiagnosticsFilename = cuda_species_resident_fast_path_0490m.csv
```

The mode is intentionally separate from
`speciesResamplingCudaResidentValidationEnable`: the validation mode keeps the
transitional equivalence machinery, while the fast path removes it.

Current safety envelope:

- fully periodic boundaries;
- no immersed solid;
- no latent activation;
- no thermal renormalization;
- CUDA species transfer planning required;
- CUDA species population guard required when the guard is enabled;
- CUDA species mass closure required when mass closure is enabled.

Unsupported combinations fail during parameter validation rather than silently
falling back to the CPU path.

## Removed host transitions

For the species donor/receiver transfer stage, the fast path removes:

- the 0490g CPU transfer plan;
- the host mirror of the 0490k plan arrays;
- the plan D2H/H2D round trip;
- the CPU passive extraction/insertion operation vector;
- the 0453 operation-array D2H round trip;
- the 0448 operation-array H2D round trip;
- the full `ParticleState` rollback copy used by the transitional shadow path;
- the full-particle-state download after transfer application.

The direct sequence is now:

```text
0490h resident species deposit
  -> 0490k resident species transfer plan
  -> 0490m exact-type donor selection and direct device mutation
  -> compact patchback of moved particles only
```

The correctness-first 0490m kernel preserves deterministic ordering: transfer
plan order followed by ascending active-particle index. It rejects particles of
the wrong type even when they lie in the selected donor cell.

## Mass-closure fast diagnostics

When the production fast path is active, 0490i also skips:

- downloads of the dense target/strength/scale/remap cell arrays;
- the per-cell CUDA/CPU deposit equivalence loop.

The closure remains applied to the shared resident particle masses. The active
mass/velocity prefix is still downloaded because the legacy post-remap CPU
deposit remains in the current orchestration.

## Validation script

Run:

```bash
LIVE_PROGRESS=1 \
BIN=build/src_mpcd_base_cuda_q6_resident_0490m \
bash scripts/run_0490m_cuda_species_resident_fast_path_validation.sh
```

The script performs:

1. the complete 0490l non-regression suite;
2. a direct device-plan handoff smoke test with a nearer incompatible gas donor
   and a farther mixed donor containing the required liquid species;
3. multi-seed integrated runs using resident periodic streaming and resident
   SRC collision before the population guard, then combining transfer planning,
   direct particle mutation, mixed-species refill support and phase-aware mass
   closure;
4. per-step audits that the CPU plan, passive operation vectors, transitional
   0453/0448 stages and full-state transfer downloads remain absent;
5. per-species mass-conservation and workspace-reuse checks;
6. timing output for the remaining CPU resampling phases.

`STEPS` and `SEEDS` are overridable. The default validation uses 100 steps for
three fixed seeds; a 1000-step confirmation can be launched with `STEPS=1000`.

## Remaining CPU scope

0490m does not yet claim a globally host-free resampling step. The following
legacy orchestration remains and is measured by the validation script:

- weighted real-fluid deposit and poor/rich classification;
- resampling-pool reconstruction;
- post-guard and post-edit deposits;
- post-remap deposit;
- active mass/velocity synchronization after 0490i;
- summary and file-output diagnostics.

These stages are the next migration target. Their removal requires a resident
replacement for the weighted deposit/classification metadata currently consumed
by 0490k and for the post-edit/post-remap host diagnostics.
