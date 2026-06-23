# 0419 files-only patch

Adds `darcyBrinkmanForcingMode=outward_bath`, an oriented thermal-bath Darcy mode using the cellwise normal

```text
n = grad(chi) / |grad(chi)|
```

to reemit the normal component toward increasing `chi`, i.e. from solid toward fluid.

Existing modes remain available:

```kv
darcyBrinkmanForcingMode = mean
darcyBrinkmanForcingMode = thermal_bath
darcyBrinkmanForcingMode = outward_bath
```

Build:

```bash
MPCD_ENABLE_LIVE_VIS=1 OUT=build/src_mpcd_base_cuda_q6_resident_0400_livevis bash scripts/build_src_mpcd_cuda_q6_resident_0400.sh
```

First validation:

```bash
DARCY_INITIAL_DEACTIVATE_BELOW_CHI=0.5 DARCY_BRINKMAN_FORCING_MODE=outward_bath WALL_KBT=-1.0 LIVE_VIS_FIELD=vorticity LIVE_VIS_EVERY=10 STEPS=3000 SUMMARY_EVERY=300 DUMP_STATE_EVERY=1000 DUMP_ROLE_FILTER=fluid FORCE_BUILD=0 TAG=vk0419_vorticity_outward_bath_3000 bash scripts/run_src_classic_cuda_darcy_chi_vonkarman_periodic_0416.sh
```

See `doc/DARCY_OUTWARD_BATH_0419.md` for details.
