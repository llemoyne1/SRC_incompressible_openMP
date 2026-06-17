# 0348a-topo: optional cell-based benchmark observables

This patch adds a first low-overhead benchmark observable path for the
Darcy/Brinkman topology branch.

## Scope

The 0348a implementation is intentionally limited to cell-based quantities
already available in the Darcy diagnostic pass.  It does **not** add section
profiles, wake profiles, pressure reconstruction, or an extra particle pass.

New optional parameters:

```text
topoBenchmarkEnable = false
topoBenchmarkEvery = 0
topoBenchmarkFilename = topo_benchmark_0348.csv
topoBenchmarkForceEnable = true
topoBenchmarkDragLiftEnable = true
topoBenchmarkFlowDirX = 1.0
topoBenchmarkFlowDirY = 0.0
topoBenchmarkLiftDirX = 0.0
topoBenchmarkLiftDirY = 1.0
```

`topoBenchmarkEvery <= 0` falls back to `darcyCostEvery`.

## Performance policy

The historical path is unchanged by default:

```text
topoBenchmarkEnable = false
```

When enabled, the force reduction is only activated on benchmark output steps,
not on every step.  The force observable adds two cell-level atomic reductions
for those sampled steps:

```text
darcyForceX = sum_c m_c alpha_c (u_x,c - u_s,x)
darcyForceY = sum_c m_c alpha_c (u_y,c - u_s,y)
```

The drag and lift proxies are projections of that integrated Darcy/Brinkman
reaction proxy onto user-defined flow and lift directions.

## Output

The benchmark CSV is written next to `darcy_cost_0343.csv`, by default:

```text
output/topo_benchmark_0348.csv
```

Columns:

```text
step,time,particles,activeFluid,numCells,mass,meanChi,meanAlpha,
darcyPower,darcyPowerPerMass,meanSpeedRms,solidLeakRms,
darcyForceX,darcyForceY,dragProxy,liftProxy,
flowDirX,flowDirY,liftDirX,liftDirY,alphaMin,alphaMax,q,chiMode
```

## Validation script

A first diagonal-channel benchmark runner is provided:

```bash
bash scripts/run_topo_darcy_diagonal_benchmark_0348a.sh
```

It reuses the 0347 diagonal-channel `chi_file` geometry and enables benchmark
force/drag/lift output.  It is still a periodic SRC-Darcy benchmark runner; a
later patch can add inlet/outlet section fluxes and RANS comparison.
