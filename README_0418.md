# 0418 files-only patch

This archive adds the optional 0418 Darcy/Brinkman features:

- `darcyInitialDeactivateBelowChi`: one-time load/restart conversion of active particles in chi-solid cells to `Inactive`.
- `darcyBrinkmanForcingMode=thermal_bath`: particle-wise stochastic Brinkman forcing that mimics a wall thermal bath without persistent wallVP particles.

The historical Darcy/Brinkman mode remains the default:

```kv
darcyBrinkmanForcingMode = mean
```

First test keys:

```kv
darcyInitialDeactivateBelowChi = 0.5
darcyBrinkmanForcingMode = thermal_bath
wallKBT = -1.0
```

Build:

```bash
MPCD_ENABLE_LIVE_VIS=1 OUT=build/src_mpcd_base_cuda_q6_resident_0400_livevis bash scripts/build_src_mpcd_cuda_q6_resident_0400.sh
```

See `doc/DARCY_THERMAL_BATH_0418.md` for details and diagnostic caveats.
