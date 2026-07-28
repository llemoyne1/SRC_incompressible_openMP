# Statut de l'expérience

> **État : archivé, non actif dans la branche `surf`.**
>
> Cette note conserve la conception de l'expérience 0493o5. Les modifications
> sources et les scripts d'analyse associés ont été retirés du répertoire de
> travail après évaluation. Le chemin de production courant reste celui issu
> de 0493o1--0493o3. Les fichiers exacts de l'expérience sont conservés dans
> l'archive externe créée avant le nettoyage.
>
> Ce document ne doit donc pas être interprété comme la description du code
> actuellement compilé.

# 0493o5 — production-light diagnostics and analytic post-split state

## Scope

0493o5 optimizes only the resolved 0493o1/0493o3 split-only support repair:

- resident active-prefix CUDA state authoritative;
- insertion enabled;
- extraction, remap, empty refill and legacy population guards disabled;
- equal-mass split `m -> m/2 + m/2` with identical daughter velocity.

Candidate selection, split ordering, budgets, positions, velocities, masses,
types and roles are unchanged. No simulation parameter or environment flag is
added.

## Existing switch reused

The existing `MPCD_INTERNAL_PROFILES` switch selects the execution mode:

- `MPCD_INTERNAL_PROFILES=1`: qualification mode retained exactly, including
  phase timing events, complete post-mutation deposit and per-step kinetic
  validation;
- `MPCD_INTERNAL_PROFILES=0`: 0493o5 production-light mode.

If 0298 moment restoration is explicitly requested, 0493o5 automatically uses
the qualification path because restoration needs the complete post-mutation
workspace.

## Analytic replacement of `depositAfter`

For a donor of mass `m`, the repair creates two particles of mass `m/2` with
the same velocity. Within the affected cell/species pair:

- mass is unchanged;
- momentum and barycentric velocity are unchanged;
- relative kinetic energy is unchanged;
- `sum(m^2)` changes by `-m^2/2`.

The existing 0493o1 applicator updates `sum(m^2)` after each split actually
applied. Therefore the final

`Neff = sum(m)^2 / sum(m^2)`

is computed exactly without a second global cell-moment deposit. The child is
also assigned the analytically known cell id so cadence-based kinetic checks
can scan the enlarged active prefix without rebuilding the cell workspace.

## Production-light diagnostics

Functional counters remain exact on every step using the existing CUDA
finalizer and the existing scalar downloads. Production-light mode suppresses:

- CUDA phase timing events and their synchronizations;
- host downloads of complete cell arrays on ordinary steps;
- cell-relative kinetic checks on ordinary steps;
- the supplemental 0493o3 caller timing CSV;
- the complete post-split global deposit.

Detailed kinetic validation is retained on:

- step 1 when the repair path reaches kinetic preparation;
- steps divisible by the existing `summaryEvery` value;
- the final step.

The main `cuda_resampling_population_guard_0297.csv` remains written every step
and gains the columns:

- `productionLight0493o5`;
- `detailedValidation0493o5`;
- `analyticPostSplit0493o5`;
- `validationEvery0493o5`;
- `analyticPostSplitSeconds0493o5`.

For every active production row, `analyticPostSplit0493o5=1` and
`depositAfterSeconds=0` are expected.

## Safety boundary

0493o5 does not optimize merge, extraction, empty refill, composition repair or
moment restoration. Those modes retain the historical qualification path.
Empty cell/species pairs remain diagnostic only.

## Validation sequence

1. Build the CUDA livevis binary.
2. Run the 200-step dual-G40 qualification case with
   `MPCD_INTERNAL_PROFILES=0` in a new run root.
3. Compare it against the validated 0493o3 reference using
   `scripts/analyze_0493o5_production_light.py --reference ...`.
4. Only after exact functional equivalence is established, rerun the 2000-step
   segmented/Darcy case with profiles disabled and compare wall time.
