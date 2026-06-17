# 0343 — CUDA-VIZ topo/Darcy Brinkman pure SRC classic

## Scope

This branch introduces a first topology-oriented Darcy/Brinkman block for the CUDA-VIZ code path, deliberately restricted to SRC classic CUDA resident runs:

```text
SRC classic -> thermostat/mean-flow stages -> Darcy/Brinkman cell-mean kick -> livevis/dumps
```

Q6/projection, chi-aware resampling and empty-refill are intentionally outside this patch.  The goal is to validate the Darcy block, the analytic topology field and the cost observables before coupling to later incompressible/resampling developments.

## Design variable convention

The design variable is

```text
chi = 1 : fluid
chi = 0 : solid / highly resistive Brinkman region
```

The implemented interpolation is

```text
alpha(chi) = alphaMin + (alphaMax-alphaMin) * q * (1-chi) / (q+chi)
```

The CUDA kick is applied to the cell mean velocity only:

```text
u* = uSolid + exp(-alpha dt) (u-uSolid)
du = u* - u
v_i <- v_i + du
```

Thus relative thermal fluctuations are not directly damped.

## Main parameters

```text
darcyBrinkmanEnable = true/false
darcyChiMode = uniform | circle | cylinder | box | rectangle
darcyUniformChi = 1.0
darcyAlphaMin = 0.0
darcyAlphaMax = 80.0
darcyQ = 0.1
darcyUSolidX = 0.0
darcyUSolidY = 0.0
darcyCircleCx = ...
darcyCircleCy = ...
darcyCircleR = ...
darcyInterfaceWidth = ...
darcyCostEvery = 20
darcyCostFilename = darcy_cost_0343.csv
```

Patch 0343 rejects `resamplingEnable=true` and `projectionEnable=true` when `darcyBrinkmanEnable=true`.

## Live visualization fields

The CUDA field renderer now accepts:

```text
chi
alpha
darcy_power
ux
uy
speed
vorticity
mass
```

`darcy_power` is visualized as `alpha |u-uSolid|^2` on the live render grid.

## Output cost CSV

When `darcyCostEvery > 0`, the solver appends:

```text
outputDir/darcy_cost_0343.csv
```

Columns:

```text
step,time,particles,activeFluid,numCells,mass,fluidVolumeFraction,meanChi,meanAlpha,
darcyPower,darcyPowerPerMass,meanSpeedRms,solidLeakRms,alphaMin,alphaMax,q,chiMode
```

## Provided scripts

Build:

```bash
MPCD_ENABLE_LIVE_VIS=1 bash scripts/build_src_mpcd_cuda_topo_0343.sh
```

Demo run:

```bash
bash scripts/run_topo_darcy_brinkman_viz_0343.sh
```

Typical runtime field changes can be made by editing:

```text
runs/topo_darcy_brinkman_viz_0343/livevis_control.kv
```
