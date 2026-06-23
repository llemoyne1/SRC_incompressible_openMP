# 0420 — Combined mean Brinkman + outward bath mode

This patch adds a combined Darcy/Brinkman forcing mode:

```kv
darcyBrinkmanForcingMode = mean_outward_bath
```

Accepted aliases:

```kv
darcyBrinkmanForcingMode = mean_oriented_bath
darcyBrinkmanForcingMode = brinkman_outward_bath
```

## Motivation

Patch 0419 added `outward_bath`, which reemits the normal component toward increasing `chi`, i.e. from solid to fluid.  However, in 0419 this mode replaced the historical mean Brinkman kick.  That made the modes exclusive:

```text
mean           : remove cell-mean leak efficiently
outward_bath   : orient/reemit particles outward, but without the mean correction
```

The 0420 mode combines both actions:

```text
1. apply the historical mean Brinkman kick
2. apply the chi-gradient outward bath
```

This preserves the strong cell-mean damping of the existing Brinkman path while adding the outward-oriented interface response.

## Unchanged modes

The previous modes remain unchanged:

```kv
darcyBrinkmanForcingMode = mean
darcyBrinkmanForcingMode = thermal_bath
darcyBrinkmanForcingMode = outward_bath
```

## First validation command

For the von Karman vorticity comparison:

```bash
DARCY_INITIAL_DEACTIVATE_BELOW_CHI=0.5 \
DARCY_BRINKMAN_FORCING_MODE=mean_outward_bath \
WALL_KBT=-1.0 \
LIVE_VIS_FIELD=vorticity LIVE_VIS_EVERY=10 \
STEPS=3000 SUMMARY_EVERY=300 DUMP_STATE_EVERY=1000 DUMP_ROLE_FILTER=fluid \
FORCE_BUILD=0 TAG=vk0420_vorticity_mean_outward_bath_3000 \
bash scripts/run_src_classic_cuda_darcy_chi_vonkarman_periodic_0416.sh
```

## Diagnostic caveat

The legacy Darcy/topology CSV force proxies remain based on the pre-existing cell-mean diagnostic.  The most relevant immediate comparison for this mode is visual/field-level vorticity and post-processing from dumps.
