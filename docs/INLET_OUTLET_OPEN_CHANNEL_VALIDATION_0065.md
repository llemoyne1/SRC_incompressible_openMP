# 0065 — Structured open-channel / Poiseuille-style inlet/outlet validation

This validation case is the first longer, structured check of the inlet/outlet
chain after the staged implementation:

- 0061/0061b: classic particle inlet/outlet recycling;
- 0062: Q6 velocity projection with open-boundary fluxes;
- 0063/0063b: Q9 mass-flux projection with open-boundary mass fluxes;
- 0064/0064b: bulk-only virial closure with inlet/outlet reservoir exclusion.

The objective is not to validate a final physical outlet model or a von Karman
wake.  The objective is to produce a reproducible open-channel reference before
reintroducing more constrained geometries.

## Default run set

The runner `scripts/run_open_channel_poiseuille_validation_0065.sh` launches
three cases by default:

| case | purpose |
|---|---|
| `q6_keepmean_s050` | Q6 open-boundary reference |
| `q9_keepmean_b0001` | Q6 + Q9 open-boundary mass-flux reference |
| `q9_virial_keepmean_K0p50_b0p05_ex3` | full liquid closure, bulk-only virial away from reservoirs |

Defaults are deliberately moderate:

```text
CASE_STEPS=3000
SUMMARY_EVERY=100
DUMP_STATE_EVERY=3000
NUM_THREADS=4
```

The cases keep the mean flow at `targetMeanUx=0.05`, as in the CUDA-like
open-channel stress tests. This keeps the validation affordable and immediately
exercises the outlet. It should not be interpreted as a final autonomous inlet
condition.

An optional no-keepMean run can be added with:

```bash
RUN_NO_KEEPMEAN=1 ./scripts/run_open_channel_poiseuille_validation_0065.sh
```

That case is diagnostic only: it checks whether the open-boundary projection
slows the plug-flow decay, but it is not the primary reference.

## Run

From the repository root:

```bash
chmod +x scripts/run_open_channel_poiseuille_validation_0065.sh
./scripts/run_open_channel_poiseuille_validation_0065.sh
```

If the initial state is missing, generate it from MATLAB:

```matlab
cd matlab
generate_open_channel_classic_state( ...
    'output','../initial_state_open_channel_64x32_g20_kbt0p01.smpcd');
cd ..
```

## Analyze

```matlab
cd matlab
S = analyze_open_channel_poiseuille_validation_0065('root','..');
cd ..
```

For a non-default run root, for example a short smoke run, use:

```matlab
cd matlab
S = analyze_open_channel_poiseuille_validation_0065( ...
    'root','..', 'runRoot','runs/test_0065_short');
cd ..
```

The analyzer writes:

```text
runs/open_channel_poiseuille_validation_0065/summary_open_channel_validation.csv
runs/open_channel_poiseuille_validation_0065/profiles/profiles_y_<case>.csv
runs/open_channel_poiseuille_validation_0065/profiles/profiles_x_<case>.csv
```

The y-profiles contain the final-state fields:

```text
rho(y), Ux(y), Uy(y), kBT(y), Pkin(y), Pvir(y), Ptot(y)
```

Profiles are averaged over the interior bulk in x, excluding the inlet/outlet
reservoir strips. By default the analyzer excludes 3 cells near the inlet and 3
near the outlet, matching the 0064 virial reservoir separation.

## Acceptance criteria

For the default keepMean cases:

- `Np` and total mass remain constant;
- `meanVx` remains close to `0.05`;
- `kBT` remains close to `0.01`;
- Q6 and Q9, when enabled, converge;
- Q9 does not degrade `stdN` relative to Q6;
- virial kick remains small compared with the thermal velocity;
- virial momentum residual after correction is zero to roundoff;
- final `minN/maxN` remain non-catastrophic;
- final profiles do not show a reservoir-driven instability in the bulk.

## Interpretation

This is a structured regression/validation case, not a definitive hydrodynamic
measurement. The flow is maintained by `keepMeanFlowEnable=true`, so the profile
is Poiseuille-style/channel-like but still a controlled open-channel test. The
case is intended to provide a clean baseline before open-boundary validation on
backward-step, cylinder, or airfoil geometries.
