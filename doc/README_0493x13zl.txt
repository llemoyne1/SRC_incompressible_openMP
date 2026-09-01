0493x13zl -- canonical replacement of the complete run_ok collection

Purpose
-------
This is intentionally NOT a semantic merge.  It replaces the 13 run_ok_*.sh
runners by the homogeneous reference-fluid collection agreed in the audit,
plus the single common runner library, checker and root livevis_control.kv.

Canonical bulk fluid
--------------------
h=1/256, gamma=8, m_liquid=1, kBT=0.125,
dt=0.0063471328149122585, rotation=120deg,
random sign ON, grid shift ON, cell_relative_rescale every step.

Canonical geometries/defaults
-----------------------------
TG             1x1       256x256, U0=.05
Poiseuille     2x1       512x256
IO same-face   1x1       256x256, U=.1
Step           2x1       512x256, U=.12
NACA           3x1       768x256, U=.1
Bend           1x1       256x256, U=.1
Dam-break      2x1       512x256, m_liq=1, g=-.01, sigma=945
Dripping       1x1.5     256x384, Uin=.1, g=-.01
Splash/puddle  3.125x1.5625 800x400, Vy=-.15, g=-.005
Injection      3x1       768x256, m_liq=1, m_gas=.1, Uin=.1
VK             reduced Zovatto: 4.6875x1.5625, 1200x400,
               D=.3125=80h, 4D upstream + 11D downstream, Re_H=280 nominal.

LiveVis
-------
All runners use ./livevis_control.kv. Defaults:
liveEvery=100, recordEnable=true, recordFields=mass,ux,uy,
recordEvery=100, filterSampleEvery=100.  live grid defaults to each runner Nx,Ny.
The common summary is compact; params.kv is not dumped in full.
