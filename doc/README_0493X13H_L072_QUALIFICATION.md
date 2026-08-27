# 0493x13h — qualification du point G08 alpha=120°, lambda/h=0.72

No source/include changes. SRC-only, thermostatted/isothermal.

## A — longitudinal damped mode
- gamma=8, alpha=120°, lambda/h=0.72
- Nx=64, Ny=16
- density amplitudes 0.04 and 0.08
- 30 realizations per amplitude
- direct damped-mode estimator and 500 bootstrap samples
- outputs: `A_Cdamp_*_0493x13h.csv`

## B — density dependence of transverse viscosity
- alpha=120°, lambda/h=0.72, U0=0.05
- six independent realizations per point
- Ny=128: gamma=3,4,6,8,12,16
- Ny=256: gamma=3,4,6,8
- primary constitutive estimator: fit of the ensemble-mean signed shear amplitude
- outputs: `B_density_*_0493x13h.csv`

## C — targeted Mach qualification
- gamma=8, alpha=120°, lambda/h=0.72
- Ma=0.2,0.5,0.7,0.9
- Nx=128,256; Ny=16; four seeds
- 3 acoustic periods
- `cs` is read from stage A when available
- `nuT` is read from stage B gamma=8 when available
- outputs: `C_Mach_*_0493x13h.csv`

## Typical execution
```
bash scripts/check_0493x13h_L072_qualification.sh
PREFLIGHT_ONLY=1 LIVE_PROGRESS=1 bash scripts/run_0493x13h_master.sh
LIVE_PROGRESS=1 bash scripts/run_0493x13h_master.sh
```
Stages can be selected with `STAGES=A`, `STAGES=B`, `STAGES=C`, or combinations such as `STAGES=A,B`.
