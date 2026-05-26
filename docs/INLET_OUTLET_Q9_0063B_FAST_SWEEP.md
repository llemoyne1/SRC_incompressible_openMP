# 0063b — Fast Q6/Q9 inlet/outlet sweep

This patch adds a short validation sweep for the 0063 open-channel inlet/outlet
implementation. It does not change the numerical kernels. It only adds a Bash
runner and a MATLAB post-processing helper.

## Purpose

The 0063 smoke test verified that Q9 can run with open boundaries. This sweep is
intended to check, at low cost, that the Q9 density relaxation remains stable and
has a measurable but controlled effect before adding the virial closure.

The default sweep is deliberately short and keeps the flow globally driven, in
the same spirit as the earlier CUDA-like validation:

- one Q6 reference case;
- three Q9 cases with increasing density relaxation beta;
- 600 time steps by default;
- no immersed solid;
- no virial kick;
- left inlet, right outlet, solid top/bottom walls;
- `keepMeanFlowEnable = true`.

Optional longer or no-keep-mean cases are controlled by environment variables in
the runner script.

## Default cases

| Case | Method | keepMean | q6 strength | q9 beta | Purpose |
|---|---:|---:|---:|---:|---|
| `q6_keepmean_s050` | Q6 | true | 0.50 | 0 | Q6 baseline |
| `q9_keepmean_b0001` | Q9 | true | 0.50 | 0.001 | 0063 reference |
| `q9_keepmean_b0005` | Q9 | true | 0.50 | 0.005 | mild stronger Q9 |
| `q9_keepmean_b0010` | Q9 | true | 0.50 | 0.010 | short stability check |

This is not a final physical open-boundary validation. It is a low-cost
regression and parameter-sanity sweep before 0064.

## Run

From the repository root:

```bash
chmod +x scripts/run_open_channel_q9_inlet_outlet_fast_sweep.sh
./scripts/run_open_channel_q9_inlet_outlet_fast_sweep.sh
```

Useful overrides:

```bash
SWEEP_STEPS=1000 ./scripts/run_open_channel_q9_inlet_outlet_fast_sweep.sh
RUN_NO_KEEPMEAN=1 SWEEP_STEPS=600 ./scripts/run_open_channel_q9_inlet_outlet_fast_sweep.sh
NUM_THREADS=8 ./scripts/run_open_channel_q9_inlet_outlet_fast_sweep.sh
```

The runner writes cases under:

```text
runs/open_channel_q9_inlet_outlet_fast_sweep/
```

## MATLAB summary

```matlab
cd matlab
S = analyze_open_channel_q9_inlet_outlet_fast_sweep('root','..');
cd ..
```

The script writes:

```text
runs/open_channel_q9_inlet_outlet_fast_sweep/summary_fast_sweep.csv
```

## Acceptance criteria for the default sweep

The expected outcome is qualitative and comparative:

- `Np` and `totalMass` remain constant;
- `q6Converged = 1` and `q9Converged = 1` for Q9 cases;
- `meanVx` remains close to the target in keep-mean cases;
- `kBT` remains close to `0.01`;
- Q9 cases should not degrade `stdN` relative to the Q6 baseline;
- increasing `q9DensityRelaxationBeta` should make `q9DensityStdRatioEstimate`
  visibly smaller, without destabilizing population or temperature.

If the no-keep-mean option is run, it should be interpreted as diagnostic only:
the particle recycling inlet is still not a full physical inlet reservoir.
