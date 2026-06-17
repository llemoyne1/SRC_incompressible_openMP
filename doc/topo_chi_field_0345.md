# 0345 — External porous/design field `chi` for CUDA-VIZ Darcy/Brinkman topo

## Goal

Patch 0345 turns the Darcy/Brinkman design variable `chi` into an external solver
input, analogous to the initial particle state.  This is the required interface
for bend-pipes, complex solids and future external topology-optimization loops.

The convention is unchanged:

```text
chi = 1 : free fluid
chi = 0 : solid / highly penalized porous material
0 < chi < 1 : transition or porous design value
```

The Brinkman interpolation remains

```text
alpha(chi) = alphaMin + (alphaMax-alphaMin) * q*(1-chi)/(q+chi)
```

## New parameters

```text
darcyChiMode = file
darcyChiFile = runs/.../chi_field.f32
darcyChiNx = Nx
darcyChiNy = Ny
darcyChiFileFormat = float32
```

Supported formats in 0345:

```text
float32 / f32
double / float64 / f64
```

The layout is always row-major, cell-centered:

```text
index = iy * Nx + ix
```

Patch 0345 intentionally requires `darcyChiNx=Nx` and `darcyChiNy=Ny`.  No
interpolation or resampling is performed inside the solver.  An optimizer or
external generator must provide the field at the MPCD grid resolution.

## CUDA-resident efficiency policy

The implementation is designed not to penalize the CUDA resident path:

1. `chi` is read once on the host during initialization;
2. `chi` is uploaded once to the GPU;
3. `alpha` and the exact Darcy kick factor
   `lambda = 1 - exp(-alpha*dt)` are precomputed once on the GPU;
4. the step kernel reads only resident arrays `d_lambda`, `d_alpha`, `d_chi`;
5. there is no per-step host/device transfer of `chi`.

Analytic modes (`circle`, `box`, `uniform`) also use the same resident path after
a one-time GPU precompute of `chi`, `alpha` and `lambda`.  The step kernel is
therefore independent of the `chi` source.

## New helper scripts

Generate a raw `float32` chi file:

```bash
python3 scripts/generate_topo_chi_field_0345.py \
  --mode circle_obstacle \
  --out runs/test/chi/circle.f32 \
  --Nx 360 --Ny 96 --Lx 1.5 --Ly 0.4 \
  --cx 0.45 --cy 0.20 --radius 0.055 --interface-width 0.01
```

Validate file mode against analytic circle mode:

```bash
bash scripts/run_topo_darcy_chi_file_circle_validation_0345.sh
```

Run a radius sweep using external chi files:

```bash
RADII="0.02 0.04 0.055 0.08 0.11" \
STEPS=1000 \
LIVE_VIS_ENABLE=0 \
bash scripts/run_topo_darcy_radius_sweep_0345.sh
```

The radius sweep writes:

```text
runs/topo_darcy_radius_sweep_0345/radius_sweep_0345_summary.csv
```

## Bend-pipe preparation

The generator also includes a first `bend_pipe` mode.  It is intended as a simple
field generator for visualization and code-path validation, not yet as a fully
calibrated benchmark:

```bash
python3 scripts/generate_topo_chi_field_0345.py \
  --mode bend_pipe \
  --out runs/test/chi/bend_pipe.f32 \
  --Nx 360 --Ny 96 --Lx 1.5 --Ly 0.4 \
  --cx 0.45 --cy 0.10 --bend-radius 0.18 --pipe-width 0.10 --interface-width 0.01
```
