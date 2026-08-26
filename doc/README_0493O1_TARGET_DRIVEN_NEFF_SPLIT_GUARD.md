# 0493o1 — target-driven effective-population split guard

## Scope

This patch introduces the first mutating reformulation of the CUDA resident
population guard.  It is selected without a new policy flag by:

```text
resamplingEnable = true
resamplingInsertionEnable = true
resamplingExtractionEnable = false
resamplingRemapEnable = false
```

For every resampling-enabled cell/species pair:

- `N == 0`: diagnose only; no local split is possible;
- `N > 0` and `Neff >= resamplingPopulationNMin`: no action;
- `N > 0` and `Neff < resamplingPopulationNMin`: split the heaviest current
  fragment repeatedly until `Neff >= resamplingPopulationNTarget`, or until a
  declared safety/resource cap prevents completion.

`Neff` is evaluated as

```text
Neff = (sum m)^2 / sum(m^2)
```

The resident species-cell deposit therefore gains one field, `massSquared`.

Candidate collection uses a compact two-pass list: a deterministic dense
cell/species prefix, followed by one linear particle scatter.  Each poor pair
then selects its retained heaviest candidates without a CUDA spin lock and
without rescanning the complete particle array.

## Split invariant

Each selected parent is replaced by two equal halves.  The daughter inherits
exactly the parent velocity:

```text
m -> m/2 + m/2
v_parent -> v_parent, v_parent
```

Mass, momentum and kinetic energy are conserved locally up to floating-point
roundoff.  The existing split-safe geometric displacement is retained.

## Resource policy

No warning state, persistence array or emergency threshold is introduced.
When the global pool or step cap is insufficient, requests are granted in the
following deterministic order:

1. lowest `Neff`;
2. largest `NTarget - Neff`;
3. smallest dense cell/species index.

The existing caps remain safety guards:

```text
resamplingPopulationMaxSplitsPerCell
resamplingPopulationMaxSplitsPerStep
```

Incomplete repair is explicitly reported.

## First qualification values

```text
resamplingPopulationNMin = 10
resamplingPopulationNTarget = 12
resamplingPopulationNMax = 32
resamplingPopulationMaxSplitsPerCell = 16
resamplingPopulationMaxSplitsPerStep = 200000
cudaResamplingEmptyRefillEnable = false
```

## Deliberate limitations of 0493o1

- empty cell/species pairs are diagnosed, not repaired;
- only the active-prefix-safe resident CUDA carrier is accepted;
- extraction/merge and global remap remain disabled in the new mode;
- `missingSplitsToTarget` is exact for pool/step/application shortages and is a
  lower bound of one when the per-cell planning cap itself is reached;
- this patch has to be compiled and exercised on the CUDA development machine;
  the generation environment does not contain the project toolchain/GPU.

## Reference validation

`scripts/test_0493o1_reference_planner.py` compares the retained
top-`(maxSplitsPerCell+1)` planner against a full greedy heap over randomized
mass distributions and verifies the equal-velocity split invariants.

## New diagnostics

The existing `cuda_resampling_population_guard_0297.csv` gains:

```text
localSupportSplitOnly0493o1
poorNonEmptyPairs0493o1
emptySpeciesPairs0493o1
requestedSplits0493o1
appliedSplits0493o1
repairedToTarget0493o1
incompleteRepairCells0493o1
missingSplitsToTarget0493o1
limitedByCellCap0493o1
limitedByStepCap0493o1
limitedByPool0493o1
noCandidatePairs0493o1
candidateCountMismatchPairs0493o1
safetyLimitedPairs0493o1
maxSplitsPerPair0493o1
minNeffBefore0493o1
minNeffAfter0493o1
```
