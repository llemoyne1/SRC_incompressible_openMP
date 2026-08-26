# 0493x11 — quantitative capillary validation

This suite is diagnostic/qualification only. It does not modify CUDA physics.

## 0493x11a — 2-D Young–Laplace law

Current production path: Q6-G-F + x10o/x10p/x10q kinetic free surface.

Default compact campaign:
- sigma=1500, R/h = 8, 12, 20, 40
- R/h=20, sigma = 500, 1500, 3000, 4500
- three seeds by default
- 256x256, h=1/256, gamma=20, dt=0.002, kBT=0.125
- 1000 steps, x9e diagnostics every 10 steps

The analysis uses `cuda_static_drop_pressure_0493x9e.csv`. This is important:
`measuredPressureJump` is reconstructed from the solved Q6 pressure potential in
deep liquid, not from the imposed `sigma*kappa` boundary value.

Primary comparison:
    Delta p_Q6 = sigma / R_eff
with
    R_eff = sqrt(alphaArea/pi).

Outputs:
- `young_laplace_runs.csv`
- `young_laplace_grouped.csv`
- `young_laplace_report.txt`
- optional PNG plots if matplotlib is installed

## 0493x11b — capillary-wave dispersion

Geometry:
- periodic x
- solid bottom/top
- liquid below a single-valued free surface, vacuum above
- H=0.25 in a 1.0 x 0.5 domain
- 256x128, h=1/256
- initial eta = H + a cos(kx), a=2h
- modes n = 2,3,4
- sigma = 1500,4500
- one seed by default (repeat with multiple seeds for publication uncertainty)

Theory:
    omega^2 = (sigma/rho) k^3 tanh(kH)
    rho = gamma*m/h^2.

The runner records `mass` on the solver grid every 20 steps with the existing
filtered recorder, with LiveVis GUI disabled. The analyzer reconstructs
alpha=clamp(cellMass/(gamma*m),0,1), computes the signed Fourier coefficient of
the liquid height, and fits a damped sinusoid without scipy/pandas.

Outputs:
- `capillary_wave_cases.csv`
- one trace CSV per case
- `capillary_wave_report.txt`
- optional dispersion/time-trace PNG plots

For a first smoke:
    SEEDS="4931101" STEPS=300 bash scripts/run_0493x11a_young_laplace_validation.sh
    SIGMAS="1500" MODES="2" STEPS=500 bash scripts/run_0493x11b_capillary_wave_validation.sh

For the intended campaigns:
    bash scripts/run_0493x11a_young_laplace_validation.sh
    bash scripts/run_0493x11b_capillary_wave_validation.sh

For capillary-wave publication uncertainty, rerun with e.g.
    SEEDS="4931201 4931202 4931203" bash scripts/run_0493x11b_capillary_wave_validation.sh
