# 0064b — Fast virial inlet/outlet sweep

This patch adds a short regression sweep for the 0064 open-channel liquid closure:

- particle inlet/outlet from 0061b;
- Q6 open-boundary velocity projection from 0062;
- Q9 open-boundary mass-flux projection from 0063;
- bulk-only virial EOS/kick from 0064, excluding inlet/outlet reservoir cells.

The goal is not to measure a final physical EOS response. The sweep is a fast stability and sensitivity check before using inlet/outlet liquid closure in longer Poiseuille, backward-step, or demonstration cases.

## Default cases

The default script runs four short keep-mean cases:

| case | `virialK` | `virialBeta` | `virialOpenBoundaryExclusionCells` | purpose |
|---|---:|---:|---:|---|
| `virial_K0p50_b0p05_ex3` | 0.50 | 0.05 | 3 | 0064 reference |
| `virial_K1p00_b0p05_ex3` | 1.00 | 0.05 | 3 | stronger EOS stiffness |
| `virial_K0p50_b0p10_ex3` | 0.50 | 0.10 | 3 | stronger kick relaxation |
| `virial_K0p50_b0p05_ex5` | 0.50 | 0.05 | 5 | larger reservoir exclusion |

The default length is deliberately short:

```bash
SWEEP_STEPS=300
SUMMARY_EVERY=100
```

This keeps the wall-clock cost close to a smoke test while still exercising the coupled Q6/Q9/virial path repeatedly.

## Run

From the repository root:

```bash
chmod +x scripts/run_open_channel_q9_virial_inlet_outlet_fast_sweep.sh
./scripts/run_open_channel_q9_virial_inlet_outlet_fast_sweep.sh
```

Useful overrides:

```bash
SWEEP_STEPS=600 ./scripts/run_open_channel_q9_virial_inlet_outlet_fast_sweep.sh
NUM_THREADS=8 ./scripts/run_open_channel_q9_virial_inlet_outlet_fast_sweep.sh
RUN_NOVIRIAL_REF=1 ./scripts/run_open_channel_q9_virial_inlet_outlet_fast_sweep.sh
```

The optional `RUN_NOVIRIAL_REF=1` adds a Q9 no-virial reference case, useful when one wants to compare the virial sweep directly to the same script output.

## MATLAB summary

From the repository root:

```matlab
cd matlab
S = analyze_open_channel_q9_virial_inlet_outlet_fast_sweep('root','..');
cd ..
```

The summary table is written to:

```text
runs/open_channel_q9_virial_inlet_outlet_fast_sweep/summary_virial_fast_sweep.csv
```

## Acceptance checks

The sweep is considered healthy if:

- `Np` and `totalMass` are unchanged;
- `meanVx` remains at the keep-mean target;
- `kBTEstimate` remains close to `0.01`;
- Q6 and Q9 are applied and converged;
- virial kick is applied for virial cases;
- `virialMomentumResidualAfterCorrection` is zero or near roundoff;
- `virialDuOverThermalRms` remains small, typically well below a few percent in this smoke regime;
- `stdN`, `minN`, and `maxN` remain comparable to 0064 and do not show reservoir blow-up.

A flat or near-zero mean `Pvir` is expected in this open-channel smoke because the density reference is `current_uniform` and the run is not a compression/EOS experiment.
