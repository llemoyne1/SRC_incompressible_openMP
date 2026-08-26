# 0493w6 — Resident post-application diagnostic for independent masked Q6

## Purpose

`0493w5` distinguishes a species' masked projected face flux from the mixture
projection and guarantees that a species with `q6StrengthDeclared=0` receives
no direct Q6 correction.  Its original `divAfterRms` diagnostic nevertheless
measures the auxiliary face flux produced by the masked Poisson solve, not the
species cell velocity obtained after the correction has been applied to the
particles.

`0493w6` adds the missing measurement without changing the Q6 operator.

## CUDA-resident path

For every enabled species, the exact pre-application occupancy mask is copied
device-to-device into a dense species-major mask buffer.  After all particle
corrections have been applied, the code:

1. resets the resident cell-species mass and momentum arrays;
2. redeposits mass and momentum directly from the resident particle state;
3. rebuilds the per-species cell velocity on the device;
4. evaluates its divergence with the exact stored support mask;
5. downloads only the existing scalar block reductions used by Q6 diagnostics.

No particle state, dense cell-species field or occupancy mask is materialised on
the host.  The shared CUDA particle state remains authoritative and fresh.

## CSV schema

The existing file is retained:

```text
cuda_species_q6_independent_masked_0493w5.csv
```

The compatibility columns remain:

```text
divAfterRms
divAfterMaxAbs
```

They still denote the projected auxiliary face flux.  Explicit columns are
added:

```text
divAfterProjectedFaceFluxRms
divAfterProjectedFaceFluxMaxAbs
divAfterAppliedCellVelocityRms
divAfterAppliedCellVelocityMaxAbs
```

The generic resident Q6 diagnostics now map:

```text
divAfterProjectedFlux*  -> projected auxiliary face flux
divAfterCellVelocity*   -> post-application per-species cell velocity
```

## Qualification

Rebuild the livevis CUDA binary, then run:

```bash
LIVE_PROGRESS=1 bash scripts/run_0493w6_independent_masked_postapply_diagnostic.sh
```

The runner reuses the `0493w5` profiles `full`, `islands`, `mixed60` and
`mixed40`.  It retains the strict projected-flux and zero-strength checks.
Strong post-application reduction is required for the full-support `full` and
`mixed60` cases.  The disconnected `islands` value is reported without a severe
threshold: it is the diagnostic intended to quantify the current masked
face-to-cell mapping error before any operator reformulation.

## Scope

This patch is diagnostic only.  It does not change:

- the occupancy support definition;
- the masked Poisson operator or interface boundary condition;
- the face-to-cell correction mapping;
- the legacy `common` and `weighted` paths;
- the periodic-only scope of `independent_masked` stage 1.
