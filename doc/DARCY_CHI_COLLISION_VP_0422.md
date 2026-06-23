# 0422 — Effective chi collision virtual particles

Patch 0422 adds a lightweight virtual-particle contribution derived from the Darcy/topology chi field.  It is deliberately not an explicit particle implementation: no virtual particles are inserted into the particle arrays, no additional slots are required, and dumps remain unchanged.

The new mode adds effective virtual mass and momentum to the SRC collision cell moments before the collision center of mass is finalized:

```text
M_eff = M_real + M_vp
P_eff = P_real + M_vp * u_wall
u_cm_eff = P_eff / M_eff
```

Only real particles are rotated and stored.  The virtual population disappears after the collision.  This approximates the wallVP/no-slip mechanism at chi interfaces at substantially lower cost than explicit virtual-particle sampling.

## Parameters

```kv
darcyChiCollisionVpEnable = false
darcyChiCollisionVpMode = interface_band
darcyChiCollisionVpGamma = -1
darcyChiCollisionVpMass = 1.0
darcyChiCollisionVpLayers = 1
darcyChiCollisionVpThreshold = 0.5
darcyChiCollisionVpStrength = 1.0
```

Semantics:

- `darcyChiCollisionVpEnable=true` activates the 0422 contribution.
- `darcyChiCollisionVpMode=interface_band` is the only mode in 0422.
- `darcyChiCollisionVpGamma<=0` falls back to `wallVpGamma`, then to inferred active-fluid gamma.
- `darcyChiCollisionVpLayers=1` adds virtual moments in the first fluid layer adjacent to cells with `chi <= threshold`.
- `darcyChiCollisionVpThreshold` separates fluid-like and solid-like chi cells.
- `darcyChiCollisionVpStrength` multiplies the effective virtual mass.
- The virtual wall velocity is `darcyUSolidX/darcyUSolidY`.

## Requirements and limitations

- Requires `darcyBrinkmanEnable=true`, because the chi device field is provided by the Darcy workspace.
- Implemented only in the CUDA persistent SRC collision path.
- It modifies the collision center of mass but does not create geometric reflection or position projection.
- It should therefore be tested with the existing chi cleanup / Brinkman controls, for example:

```kv
darcyInitialDeactivateBelowChi = 0.5
darcyBrinkmanForcingMode = mean
darcyChiCollisionVpEnable = true
darcyChiCollisionVpGamma = -1
darcyChiCollisionVpLayers = 1
darcyChiCollisionVpStrength = 1.0
```

The intended diagnostic question is whether the von Karman vorticity and wake move closer to the immersed-solid mode while keeping the cost much lower than explicit VP insertion.
