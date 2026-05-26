# 0065b — Open-channel bulk/core diagnostics

This patch does not modify the numerical solver.  It only enriches the MATLAB
post-processing of the 0065 open-channel / Poiseuille validation case.

## Motivation

The 0065 validation produced smooth and physically plausible `Ux(y)` profiles,
but the global runtime extrema `minN` and `maxN` are too sensitive to boundary
cells.  A few instantaneously empty cells near walls or inlet/outlet reservoir
slabs should not be interpreted as a bulk instability.

0065b therefore separates three diagnostics:

- **global runtime extrema**, read from `summary_runtime.csv`;
- **bulk final-state diagnostics**, excluding inlet/outlet reservoir slabs;
- **core final-state diagnostics**, excluding both inlet/outlet reservoir slabs
  and near-wall rows.

This gives a more robust criterion before moving to an open backward-facing step
or an immersed-solid demonstration.

## Definitions

For the default left-inlet/right-outlet channel:

- `profileOpenExclusionCells = virialOpenBoundaryExclusionCells` by default,
  unless overridden from MATLAB;
- bulk cells exclude the first and last `profileOpenExclusionCells` x-columns
  adjacent to open boundaries;
- `profileWallExclusionCells = excludeWallCells`;
- core cells are bulk cells excluding the first and last
  `profileWallExclusionCells` y-rows.

The open exclusion can be overridden with:

```matlab
S = analyze_open_channel_poiseuille_validation_0065( ...
    'root','..', 'openExclusionCells',3, 'excludeWallCells',2);
```

## New summary fields

The 0065 summary CSV gains robust population fields such as:

```text
profileBulkCellCount
profileBulkCountMean
profileBulkCountStd
profileBulkCountMin
profileBulkCountMax
profileBulkEmptyCellFraction
profileBulkMinCountXIndex
profileBulkMinCountYIndex
profileBulkMaxCountXIndex
profileBulkMaxCountYIndex

profileCoreCellCount
profileCoreCountMean
profileCoreCountStd
profileCoreCountMin
profileCoreCountMax
profileCoreEmptyCellFraction
profileCoreRhoMean
profileCoreRhoStd
profileCoreKBTMean
profileCoreUxMean
profileCoreUxStd
profileCoreUyMean
profileCoreUyRms
```

The quadratic velocity fit also gains explicit coefficients and residuals:

```text
profileUxQuadraticA
profileUxQuadraticB
profileUxQuadraticC
profileUxQuadraticRMSE
profileUxQuadraticNPoints
```

## Updated profile CSVs

`profiles_y_<case>.csv` now includes:

```text
isWallExcludedForCore
isUsedForQuadraticFit
```

`profiles_x_<case>.csv` now includes:

```text
isOpenReservoirExcluded
isActiveForBulk
```

## Recommended acceptance criteria

For the current 64 x 32 open-channel validation, the important criteria are now:

```text
Np and total mass conserved
meanVx maintained for keepMean cases
Q6/Q9 converged
kBT close to 0.01
profileCoreCountMin not catastrophically low
profileCoreCountMax not catastrophically high
profileCoreEmptyCellFraction close to 0
profileUxQuadraticR2 remains high
virialMomentumResidualAfterFinal = 0 for virial cases
virialDuOverThermalRmsFinal remains small
```

Global `minNFinal = 0` is no longer by itself a rejection criterion if the core
population diagnostics remain clean.
