# 0418 — Darcy/Brinkman initial chi cleanup and thermal-bath forcing

This patch keeps the historical Darcy/Brinkman path unchanged by default and adds two optional mechanisms for chi-based solid approximations.

## 1. Initial chi-solid cleanup

New parameter:

```kv
# Negative disables the cleanup.  Otherwise, at load/restart time only,
# Fluid particles located in cells with chi < threshold become Inactive.
darcyInitialDeactivateBelowChi = -1
```

Recommended first test for binary chi fields:

```kv
darcyInitialDeactivateBelowChi = 0.5
```

This is an initial/restart operation only.  It does not add a per-step role-change or compaction mechanism.  The goal is simply to avoid carrying useless active particles initially located in the chi-solid region.  If `initialInactiveSlots` is also used, the cleanup is applied after the inactive reservoir has been ensured, and the active-fluid prefix is compacted once.

## 2. Alternative thermal-bath Brinkman forcing

New parameter:

```kv
# Default/historical mode:
darcyBrinkmanForcingMode = mean

# New 0418 mode:
darcyBrinkmanForcingMode = thermal_bath
```

The default `mean` mode is the existing cell-mean Brinkman kick.  The new `thermal_bath` mode applies a particle-wise stochastic relaxation:

```text
v_i' = u_solid + a (v_i - u_solid) + sqrt(1 - a^2) sqrt(kBT_wall / m_i) xi
```

where

```text
a = exp(-alpha(chi) dt)
```

The existing `lambdaField` stores `1 - exp(-alpha dt)`, so the implementation uses `a = 1 - lambdaField[cell]`.

`kBT_wall` is selected as:

```text
wallKBT if wallKBT > 0
else wallVpKBT if wallVpKBT > 0
else kBT
```

Thus, setting `wallKBT = -1` makes the thermal bath inherit the bulk `kBT`, while an explicit positive `wallKBT` can impose a different wall-bath temperature.

## Suggested parameters for first tests

For a binary chi obstacle:

```kv
darcyInitialDeactivateBelowChi = 0.5
darcyBrinkmanForcingMode = thermal_bath
wallKBT = -1.0
```

Keep `darcyAlphaMax`, `darcyQ`, and `dt` as in the current Brinkman tests at first, so the change isolates the forcing model.

## Diagnostics caveat

The existing `darcy_cost_0343.csv` and `topo_benchmark_0348.csv` are still written.  In `thermal_bath` mode, the historical force proxies are still computed from the pre-application cell-mean Brinkman field.  They remain useful for comparison, but they are not yet a direct stochastic momentum-exchange integral of the thermal-bath kernel.  A later diagnostics patch should separate:

```text
solidMeanLeakRms
solidThermalRms
solidParticleRms
thermalBathMomentumExchangeX/Y
```

## Build

```bash
MPCD_ENABLE_LIVE_VIS=1 OUT=build/src_mpcd_base_cuda_q6_resident_0400_livevis bash scripts/build_src_mpcd_cuda_q6_resident_0400.sh
```

## Minimal run example

Add the two new keys to a Darcy/chi `.kv` or to the generating script, then run as usual.  For the von Karman script:

```bash
FORCE_BUILD=0 bash scripts/run_src_classic_cuda_darcy_chi_vonkarman_periodic_0416.sh
```
