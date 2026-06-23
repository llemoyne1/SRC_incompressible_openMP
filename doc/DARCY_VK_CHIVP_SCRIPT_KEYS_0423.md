# 0423 — Darcy VK script chiVP parameter passthrough

This small script update adds the 0422 chi collision virtual-particle parameters to `run_src_classic_cuda_darcy_chi_vonkarman_periodic_0416.sh`.

New environment variables:

```bash
DARCY_CHI_COLLISION_VP_ENABLE=false
DARCY_CHI_COLLISION_VP_MODE=interface_band
DARCY_CHI_COLLISION_VP_GAMMA=-1
DARCY_CHI_COLLISION_VP_MASS=1.0
DARCY_CHI_COLLISION_VP_LAYERS=1
DARCY_CHI_COLLISION_VP_THRESHOLD=0.5
DARCY_CHI_COLLISION_VP_STRENGTH=1.0
```

The generated `.kv` file now contains:

```kv
darcyChiCollisionVpEnable = ...
darcyChiCollisionVpMode = ...
darcyChiCollisionVpGamma = ...
darcyChiCollisionVpMass = ...
darcyChiCollisionVpLayers = ...
darcyChiCollisionVpThreshold = ...
darcyChiCollisionVpStrength = ...
```

This is required by `run_vk_final_comparison_0423.sh` for the chiVP modes.
