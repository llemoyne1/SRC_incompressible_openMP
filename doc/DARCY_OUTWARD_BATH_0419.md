# 0419 — Oriented/outward Darcy thermal bath

This patch extends the optional Darcy/Brinkman forcing modes introduced in 0418 while keeping the historical `mean` mode unchanged.

## New forcing mode

```kv
darcyBrinkmanForcingMode = outward_bath
```

Aliases accepted by the parser:

```kv
darcyBrinkmanForcingMode = oriented_bath
darcyBrinkmanForcingMode = oriented_thermal_bath
darcyBrinkmanForcingMode = diffuse_reflection
```

## Principle

The code precomputes a cell normal from the fixed chi field:

```text
n = grad(chi) / |grad(chi)|
```

Since `chi=0` is solid and `chi=1` is fluid, `grad(chi)` points from the solid toward the fluid.  The new mode uses this normal to orient the thermalized normal velocity outward from the solid.

For each active fluid particle in a penalized/interface cell, the velocity relative to the solid velocity is decomposed as:

```text
v_rel = v - u_solid
v_n   = v_rel . n
v_t   = v_rel . t
```

with `t=(-n_y,n_x)`.  The tangential component is OU-thermalized.  The normal component is OU-thermalized and then mirrored with `abs(...)`, so it points toward increasing `chi`, i.e. away from the solid.

This is not an exact geometric wall reflection; it is a low-cost cellwise diffuse outward bath based on the chi interface.

## Cost

Compared with `thermal_bath`, the added cost is:

- two additional resident float fields: `normalX`, `normalY`;
- one precompute kernel when the chi field changes;
- two additional field reads and a few arithmetic operations per active particle in the Darcy kernel.

There is no per-step compaction, no new persistent particle role, and no particle-wall intersection search.

## Suggested validation

Use the same von Karman vorticity test as for `mean` and `thermal_bath`:

```bash
DARCY_INITIAL_DEACTIVATE_BELOW_CHI=0.5 \
DARCY_BRINKMAN_FORCING_MODE=outward_bath \
WALL_KBT=-1.0 \
LIVE_VIS_FIELD=vorticity LIVE_VIS_EVERY=10 \
STEPS=3000 SUMMARY_EVERY=300 DUMP_STATE_EVERY=1000 DUMP_ROLE_FILTER=fluid \
FORCE_BUILD=0 TAG=vk0419_vorticity_outward_bath_3000 \
bash scripts/run_src_classic_cuda_darcy_chi_vonkarman_periodic_0416.sh
```

## Diagnostic caveat

The legacy `darcy_cost_0343.csv` and `topo_benchmark_0348.csv` still use the pre-existing mean-cell Brinkman diagnostics.  They do not yet report the actual stochastic/outward momentum exchange of this new kernel.  Visual vorticity and dump post-processing remain the most meaningful checks for 0419.
