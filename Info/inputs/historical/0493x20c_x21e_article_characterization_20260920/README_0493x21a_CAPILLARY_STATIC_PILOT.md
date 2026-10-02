# 0493x21a — static capillary mechanism pilot

Purpose: validate one well-resolved static Young–Laplace pair before any radius sweep.
No solver/CUDA source is modified.

## Physical point

- model: `src-q6-g-f`
- qualified free-surface chain: x9 sigma*kappa + x10o + CIC + Q2 + x10p/q + x10u + x10v full-vector + x12a
- grid: 256 x 256, Lx=Ly=1, h=1/256
- gamma=8
- alpha_SRC=120 deg
- dt=0.0063471328149122585
- kBT=0.125, particle mass=1
- random rotation sign ON, grid shift ON
- thermostat: cell-relative rescale every step
- drop: R/h=64, centered, zero initial velocity
- gravity=0
- surface-tension cutoff: Rmin/h=4
- x12a local radius: Rc/h=25.298221281347036 (selected as in production but expected inactive for R/h=64)
- seed=4932101

Paired runs:
1. sigma=0 baseline
2. sigma=10000 active

R/h=64 is deliberately far from the special small-structure regime:
R/Rc=2.53 and R/Rmin=16, with 64 cells of wall clearance.

## Install

Extract this bundle at the repository root. It adds only two scripts.

## Preflight

```bash
LIVE_PROGRESS=1 bash scripts/run_0493x21a_capillary_static_pilot.sh --preflight
```

## Run

```bash
LIVE_PROGRESS=1 bash scripts/run_0493x21a_capillary_static_pilot.sh --run
```

Default campaign root:

`runs/0493x21a_capillary_static_pilot_R64`

## Analyze existing run only

```bash
bash scripts/run_0493x21a_capillary_static_pilot.sh --analyze
```

## Decisive outputs

- `pilot_analysis/capillary_pilot_decision_0493x21a.txt`
- `pilot_analysis/capillary_pilot_realization_0493x21a.csv`
- `pilot_analysis/capillary_pilot_timeseries_0493x21a.csv`
- `audit/traceability_0493x21a.txt`

The existing x12yl outputs are retained in parallel under `analysis/`.

## Plateau rule

The analyzer searches successive tails beginning at 30, 40, 50, 60 and 70% of the paired time history. The earliest tail with at least 20 samples satisfying all of

- R_eff normalized drift <= 1%
- p3 curvature normalized drift <= 5%
- paired capillary pressure increment normalized drift <= 10%
- alpha-area normalized drift <= 2%

is selected. If none qualifies, the pilot is stopped before any multi-radius sweep.

## Working pilot gates

These gates are screening criteria, not manuscript claims.

PASS requires no hard/review flags. REVIEW blocks automatic progression until inspected.
Hard-stop examples include curvature error >20%, sigma_eff error >30%, limiter clipping >1%, large geometry drift, or large spurious-current ratios. Tighter review bands begin at 10% curvature error, 15% sigma error, 0.1% limiter clipping, U_sp,rms/U_sigma >0.10 or U_sp,max/U_sigma >0.30.

No full radius campaign should be launched unless the pilot decision is
`PILOT_READY_FOR_RESOLVED_RADIUS_SWEEP` or a REVIEW has been explicitly resolved from the diagnostic time series.
