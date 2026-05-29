# Patch 0121 — local mass/momentum remap after insertion

This patch adds the first local remap stage for the OpenMP weighted-resampling
core.

It is deliberately limited: it operates only after the controlled extraction and
insertion path introduced in patches 0119 and 0120.  It does not implement the
full MATLAB thermal renormalisation yet.

## New parameter

```text
resamplingRemapEnable = false
```

The default is `false`, so all existing SRC/Q6 validations and previous
resampling smoke tests remain unchanged.

The current validation requires:

```text
resamplingExtractionEnable = true
resamplingInsertionEnable  = true
resamplingRemapEnable      = true
```

## Algorithm

After extraction and insertion, the code recomputes the real-fluid deposit.  For
each wet, non-empty cell, it computes:

```text
s_c = M_target / M_c
```

and applies the uniform local mass scaling:

```text
m_p <- s_c m_p
```

for all true-fluid particles in that cell.

Velocities are left unchanged.  Consequently:

```text
M_c after = M_target
U_c after = U_c before
P_c after = M_target U_c before
```

This is the first mass/momentum-consistent remap layer.  It is not yet the full
MATLAB remap because it does not preserve or reconstruct the local thermal
energy `E_th,c`.

## Diagnostics

The runtime summary adds:

```text
resampRemapApplyAttempted
resampRemapApplied
resampRemapCellsConsidered
resampRemapCellsRemapped
resampRemapParticlesRemapped
resampRemapSkippedDryCells
resampRemapSkippedEmptyCells
resampRemapSkippedInvalidMassCells
resampRemapTargetCellMass
resampRemapMassBefore
resampRemapMassAfter
resampRemapMassTargetSum
resampRemapMassDelta
resampRemapMomentumXBefore
resampRemapMomentumYBefore
resampRemapMomentumXAfter
resampRemapMomentumYAfter
resampRemapMomentumXTarget
resampRemapMomentumYTarget
resampRemapMomentumResidualRms
resampRemapMomentumResidualMaxAbs
resampRemapMaxCellMassRelResidual
resampRemapScaleMin
resampRemapScaleMax
resampFirstRemappedCell
resampLastRemappedCell
resampRemapAllRemappedCellsNonEmpty
```

## Smoke test

```bash
./scripts/run_resampling_local_remap_smoke_0121.sh
```

The smoke builds a 32-cell periodic case with target mass 4 per wet cell and a
balanced total true-fluid mass of 128.  The controlled extraction/insertion step
intentionally leaves one receiver cell with mass 4.5 and the donor with mass
3.5.  The remap must scale those cells back to mass 4 while preserving their
cell velocities.

Expected core output:

```text
local remap: remappedCells=2 particles=125 MRelRms≈2e-17 scaleMin≈0.8889 scaleMax≈1.1429

[0121 resampling local remap smoke] OK: local mass/momentum remap enforces M_c target while preserving cell velocities.
```

## Scope deliberately left for later

Not implemented in this patch:

- local thermal-energy preservation / `E_th,c` renormalisation;
- mass safety bounds / limiter;
- stochastic or solid-aware receiver placement;
- latent wetting activation;
- multi-step physical TG/Poiseuille validation.
