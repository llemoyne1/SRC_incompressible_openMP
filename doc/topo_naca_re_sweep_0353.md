# 0353-topo: calibrated high-resolution NACA sweep

This patch adds a higher-resolution NACA sweep runner and MATLAB-only plotting
for the polar proxy.

It does not modify the solver and does not require recompilation.

## Calibration used by default

The default sweep uses the Poiseuille viscosity calibration obtained at:

- `Ny = 160`
- `gamma = 10`
- `kBT = 0.01`
- `dt = 5e-4`
- `nu_eff = 0.002327998935968954`

The default NACA sweep is therefore tagged with a reference effective Reynolds

```text
Re_eff = U0 * chord / nu_eff
```

## Main runner

```bash
BIN=build/src_mpcd_base_cuda_topo_0348a \
NX=600 NY=160 GAMMA=10 KBT=0.01 DT=0.0005 \
U0=1.0 CHORD=0.22 \
NU_EFF_REF=0.002327998935968954 \
AOAS="-14 -12 -10 -8 -6 -4 -2 0 2 4 6 8 10 12 14" \
STEPS=2500 \
bash scripts/run_topo_darcy_naca_re_sweep_0353.sh
```

The runner writes:

- `runs/topo_darcy_naca_re_sweep_0353/naca_re_sweep_0353_summary.csv`
- `runs/topo_darcy_naca_re_sweep_0353/naca_re_polar_proxy_0353.csv`

Each angle is post-processed through the 0348b window statistics.

## MATLAB plots

```bash
POLAR_CSV=runs/topo_darcy_naca_re_sweep_0353/naca_re_polar_proxy_0353.csv \
OUT_DIR=runs/topo_matlab_plots_0353 \
SHOW_FIGURES=false \
bash scripts/run_matlab_topo_naca_re_plots_0353.sh
```

Generated plots include:

- lift proxy vs AoA
- drag proxy vs AoA
- signed finesse proxy vs AoA
- absolute finesse proxy vs AoA
- Darcy power vs AoA
- lift-vs-drag polar proxy

The MATLAB script also exports:

- `naca_re_polar_proxy_0353_sorted.csv`
- `naca_re_polar_proxy_0353_compact.csv`

## Notes

The comparison to real NACA polars remains qualitative.  The SRC-Darcy proxy does
not yet provide calibrated aerodynamic coefficients; it provides consistent
force-like proxies from the Brinkman penalization field.
