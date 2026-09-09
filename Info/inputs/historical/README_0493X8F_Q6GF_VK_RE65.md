# 0493x8f — Q6GF Von Karman Re≈65

This runner changes no C++/CUDA source.

## Fixed microscopic fluid

The reference run keeps the freshly qualified Q6GF transport signature:
- cell size a = 1/256
- gamma = 20
- dt = 0.002
- kBT = 0.125
- particle mass = 1
- SRD rotation = pi/2 with random sign
- random grid shift
- cell_relative_rescale thermostat every step
- resampling off
- Q6GF signed-density production profile, tau=0.25, tolerance 1e-5, x7j CG.

Fresh TG viscosity:
nu = 0.00067432658123431854.

## VK design

- Uinf = 0.14
- D = 0.3125 = 80 cells
- Re = U D / nu = 64.8795
- H = 1.5625 = 5D = 400 cells
- Lx = 3.125 = 10D = 800 cells
- cylinder center x=0.9375=3D, y=H/2
- 7D downstream
- left full-height hard-cell-density inlet
- right full-height passive Neumann outlet
- top/bottom physical no-slip walls
- no body force, no keep-mean-flow
- uniform initial U=0.14
- Darcy cylinder alpha=4000, forcing=mean, chi collision VP off.

The nominal cs reference is retained only as a diagnostic velocity ratio.

## LiveVis and output cost

LIVE_VIS_ENABLE is deliberately forced to 1.

Default LiveVis:
- field=speed
- every 20 steps
- 800x400 grid
- hold on exit.

Filtered recording stays enabled for later wake analysis:
- rho, ux, uy
- every 100 steps
- stride 2 -> 400x200 recorded grid.

Full particle dumps are sparse: every 10000 steps.

## Timing interpretation

Using St≈0.15 only for sizing:
- expected shedding period ≈ 14.88
- ≈ 7440 steps per period
- 20000 steps ≈ 2.69 expected periods.

This first long run is intended to establish whether a clear antisymmetric wake
and periodic lift develop. A longer production run should only be launched
after that is observed.

## Run sequence

1. PREFLIGHT_ONLY=1
2. STEPS=200 smoke
3. 20000-step qualification run

See COMMANDS_0493x8f.txt.
