# 0493x23a — JCP Section 4.1 forced Taylor–Green validation

## Purpose

Two runs only, from one byte-identical initial particle state:

- `src` → article label **SRC**;
- `src-q6-g-f` → article label **SRC + particle/field closure**.

This campaign does not recalibrate viscosity.  It measures two time-dependent observables:

1. vortex-core population ratio `R_rho = N_core/<N>domain` using four circular cores of radius `2h`;
2. normalized vector correlation `C_TG` between the reconstructed cell velocity and the imposed Taylor–Green `(1,1)` spatial mode.

## Frozen physical point

- `Nx=Ny=256`, `Lx=Ly=1`, `h=1/256`;
- `gamma=8`, `m=1`, `kBT=0.125`;
- SRC rotation angle `120 deg`, random sign, grid shift;
- `dt=0.0063471328149122585` (`lambdaMean/h = 0.72`);
- initial TG amplitude `U0=0.05`;
- continuous divergence-free TG forcing amplitude `0.2`, mode `(1,1)`;
- `10000` steps; state dump every `125` steps (~80 late-time samples plus shared step 0);
- LiveVis OFF, filtered recording OFF, resampling OFF.

The forcing and run duration preserve the historically discriminating forced-TG test, while the microscopic point is the nominal article point.

## Closure path

The closure run uses the current production route:

- `q6ForceProjectionMode=prestream_single_fused`;
- `speciesQ6Mode=free_surface_masked`;
- `tau_rho=0.25`;
- compression threshold `3/gamma`, traction threshold `6/gamma`, gain 1;
- x6c/x6e/x6f/B1 enabled, monophase x6g disabled;
- CUDA `auto_fv_cg`, tolerance `1e-5`, max iterations 800;
- x7j resident CG ON, 0407 single-block OFF.

## Preflight

```bash
cd /mnt/e/SRC_MPCD_DEV/SRC_GPU-SURF
unzip -o patch_0493x23a_article_forced_tg_validation.zip
bash -n scripts/run_0493x23a_article_forced_tg_validation.sh
python3 -m py_compile scripts/check_0493x23a_article_forced_tg_preflight.py scripts/analyze_article_forced_tg_0493x23a.py
PREFLIGHT_ONLY=1 LIVE_PROGRESS=1 bash scripts/run_0493x23a_article_forced_tg_validation.sh
```

The preflight does not generate the 256² particle state and does not launch the solver. It validates the frozen binary SHA, both production routes, shared `inputState`, forcing, common physical parameters, and closure ordering.

## Production launch

```bash
LIVE_PROGRESS=1 bash scripts/run_0493x23a_article_forced_tg_validation.sh
```

The runner generates the initial state exactly once, records its SHA-256, runs SRC then closure, and automatically performs the offline analysis.

## Outputs

```text
article_forced_tg_validation/
|-- init/initial_forced_tg.smpcd
|-- data/forced_tg_timeseries.csv
|-- data/forced_tg_summary.csv
|-- figures/fig_10_forced_taylor_green_validation.pdf
|-- figures/fig_10_forced_taylor_green_validation.png
|-- figures/check_density_src.png
|-- figures/check_density_closure.png
|-- figures/check_velocity_src.png
|-- figures/check_velocity_closure.png
|-- scripts/analyze_article_forced_tg.py
|-- params/src_params_used.kv
|-- params/closure_params_used.kv
|-- logs/...
|-- runs/src/output/...
|-- runs/closure/output/...
|-- forced_tg_validation_summary.txt
|-- traceability.txt
`-- README.txt
```

No a-priori PASS/FAIL threshold is imposed on `R_rho` or `C_TG`.
