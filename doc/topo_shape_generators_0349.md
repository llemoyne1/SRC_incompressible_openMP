# 0349-topo: obstacle and NACA chi-field generators

This patch extends the external `chi_file` generator with qualitative obstacle
families for topology/benchmark tests:

- `channel_cylinder`
- `channel_ellipse`
- `naca4_airfoil`

The convention is unchanged:

```text
chi = 1 : free fluid
chi = 0 : solid / penalized material
```

## Generator examples

Cylinder:

```bash
python3 scripts/generate_topo_chi_field_0345.py \
  --mode channel_cylinder \
  --out runs/test/chi/cylinder.f32 \
  --Nx 360 --Ny 96 --Lx 1.5 --Ly 0.4 \
  --cx 0.55 --cy 0.20 --radius 0.05 --interface-width 0.008
```

Ellipse:

```bash
python3 scripts/generate_topo_chi_field_0345.py \
  --mode channel_ellipse \
  --out runs/test/chi/ellipse.f32 \
  --Nx 360 --Ny 96 --Lx 1.5 --Ly 0.4 \
  --cx 0.55 --cy 0.20 --ellipse-a 0.10 --ellipse-b 0.035 \
  --angle-deg 0 --interface-width 0.008
```

NACA 0012:

```bash
python3 scripts/generate_topo_chi_field_0345.py \
  --mode naca4_airfoil \
  --out runs/test/chi/naca0012.f32 \
  --Nx 360 --Ny 96 --Lx 1.5 --Ly 0.4 \
  --naca 0012 --chord 0.22 --airfoil-cx 0.55 --airfoil-cy 0.20 \
  --aoa-deg 4 --interface-width 0.006
```

## Validation runners

Qualitative channel obstacle comparison:

```bash
bash scripts/run_topo_darcy_channel_shapes_0349.sh
```

NACA incidence sweep:

```bash
bash scripts/run_topo_darcy_naca_sweep_0349.sh
```

Both runners enable the 0348a benchmark observables and call the 0348b window
statistics postprocessor.  The goal is qualitative ranking of drag/lift/power
proxies before introducing a fully calibrated inlet/outlet aerodynamic benchmark.
