# Patch 0422 — chi collision virtual particles

This files-only patch adds an effective chi-derived virtual-particle contribution to the CUDA persistent SRC collision.

New parameters:

```kv
darcyChiCollisionVpEnable = true
darcyChiCollisionVpMode = interface_band
darcyChiCollisionVpGamma = -1
darcyChiCollisionVpMass = 1.0
darcyChiCollisionVpLayers = 1
darcyChiCollisionVpThreshold = 0.5
darcyChiCollisionVpStrength = 1.0
```

No explicit virtual particles are created.  The kernel only adds virtual mass and virtual momentum to the cell moments before the collision center of mass is finalized.  The virtual wall velocity is taken from `darcyUSolidX/Y`.

Suggested first VK test:

```bash
DARCY_INITIAL_DEACTIVATE_BELOW_CHI=0.5 DARCY_BRINKMAN_FORCING_MODE=mean WALL_KBT=-1.0 DARCY_CHI_COLLISION_VP_ENABLE=1 DARCY_CHI_COLLISION_VP_GAMMA=-1 DARCY_CHI_COLLISION_VP_LAYERS=1 DARCY_CHI_COLLISION_VP_STRENGTH=1.0 LIVE_VIS_FIELD=vorticity LIVE_VIS_EVERY=10 STEPS=3000 SUMMARY_EVERY=300 DUMP_STATE_EVERY=1000 DUMP_ROLE_FILTER=fluid FORCE_BUILD=0 TAG=vk0422_chi_collision_vp_mean_3000 bash scripts/run_src_classic_cuda_darcy_chi_vonkarman_periodic_0416.sh
```

The run script must write the corresponding KV keys into the generated `.kv` file.  If it does not yet do so, add:

```bash
DARCY_CHI_COLLISION_VP_ENABLE=${DARCY_CHI_COLLISION_VP_ENABLE:-0}
DARCY_CHI_COLLISION_VP_GAMMA=${DARCY_CHI_COLLISION_VP_GAMMA:--1}
DARCY_CHI_COLLISION_VP_LAYERS=${DARCY_CHI_COLLISION_VP_LAYERS:-1}
DARCY_CHI_COLLISION_VP_STRENGTH=${DARCY_CHI_COLLISION_VP_STRENGTH:-1.0}
```

and in the KV block:

```kv
darcyChiCollisionVpEnable = $DARCY_CHI_COLLISION_VP_ENABLE
darcyChiCollisionVpGamma = $DARCY_CHI_COLLISION_VP_GAMMA
darcyChiCollisionVpLayers = $DARCY_CHI_COLLISION_VP_LAYERS
darcyChiCollisionVpStrength = $DARCY_CHI_COLLISION_VP_STRENGTH
```
