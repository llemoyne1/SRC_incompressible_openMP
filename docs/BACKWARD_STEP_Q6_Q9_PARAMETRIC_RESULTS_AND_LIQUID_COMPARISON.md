# Backward-step Q6/Q9 tuning and liquid-closure comparison

This note documents the 96x48 periodic-x forced backward-step parameter sweep
performed after adding the immersed-solid projection mask.  The case is not yet
an inlet/outlet benchmark; it is a controlled separated-flow stress test for the
quasi-incompressible closure.

## Main validation question

The sweep is meant to separate three effects that were initially conflated by
simple vorticity-RMS diagnostics:

1. density/population reliability in the separated region;
2. preservation of coherent large-scale separated structures;
3. numerical consistency of Q6/Q9 with the immersed solid mask.

The key methodological finding is that the classic SRC/MPCD run exhibits larger
apparent downstream vorticity, but its recirculation cells are much less
reliably populated.  The quasi-incompressible runs produce lower total vorticity
but better-supported and more spatially organized fields.

## Sweep summary

Default sweep parameters:

- geometry: immersed rectangle step, 96x48, periodic x, solid y walls;
- forcing: `bodyAccelerationX = 0.015`;
- thermal scale: `kBT = 0.0025`;
- duration: `nSteps = 30000`;
- Q6 strengths: 0.25, 0.50, 0.75, 1.00;
- Q9 cases: `q6ProjectionStrength = 0.50`, `lowK = 2 or 4`, beta sweep.

Representative results from the completed sweep:

| case | solid leak Q6 RMS | std(N) | P05(N) reversed/ref | N<5 reversed | CV(N) reversed | omega RMS | omega low-k fraction | largest reversed comp. | reversed components |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| classic | 0 | 13.53 | 0.031 | 0.381 | 0.454 | 0.139 | 0.045 | 0.143 | 36 |
| Q6 s=0.25 | 2.28e-3 | 7.79 | 0.514 | 0 | 0.120 | 0.0856 | 0.106 | 0.111 | 41 |
| Q6 s=0.50 | 1.39e-3 | 7.69 | 0.686 | 0 | 0.107 | 0.0782 | 0.131 | 0.188 | 38 |
| Q6 s=0.75 | 6.63e-4 | 7.65 | 0.642 | 0 | 0.105 | 0.0741 | 0.154 | 0.084 | 41 |
| Q6 s=1.00 | 0 | 7.62 | 0.696 | 0 | 0.100 | 0.0703 | 0.172 | 0.157 | 31 |
| Q9 s=0.50 beta=2.5e-4 k=2 | 1.35e-3 | 7.71 | 0.687 | 0.0135 | 0.124 | 0.0797 | 0.155 | 0.135 | 34 |
| Q9 s=0.50 beta=1e-3 k=2 | 1.34e-3 | 7.70 | 0.710 | 0 | 0.103 | 0.0783 | 0.165 | 0.355 | 25 |
| Q9 s=0.50 beta=4e-3 k=2 | 1.35e-3 | 7.67 | 0.665 | 0 | 0.107 | 0.0752 | 0.157 | 0.138 | 39 |
| Q9 s=0.50 beta=1e-3 k=4 | 1.35e-3 | 7.68 | 0.731 | 0 | 0.104 | 0.0781 | 0.151 | 0.160 | 29 |

## Interpretation

The classic case is not a reliable quantitative reference in the recirculation
zone.  It has high apparent vorticity, but the low-tail population diagnostics
show that the reconstructed fields in the reversed region are strongly
under-sampled.  In contrast, Q6/Q9 maintain a much healthier population in the
separated zone:

- the 5th percentile population in the reversed zone rises from only a few
  percent of the fluid reference population in classic to roughly 50--73% in
  Q6/Q9;
- cells with fewer than 5 particles disappear in most Q6/Q9 cases;
- the temporal population CV in the recirculation drops by roughly a factor of
  four.

The large-scale vorticity content also increases strongly under Q6/Q9.  The
quantity `omegaMeanLowKFractionDownstream` is therefore more informative than
`omegaRmsDownstream` alone: it shows that Q6/Q9 do not simply destroy structures;
they remove a large amount of high-frequency particle noise and leave better
organized large-scale fields.

## Important correction introduced after the sweep

The initial implementation of `q6ProjectionStrength < 1` under-relaxed all Q6
faces, including immersed-solid faces.  This was useful for exploratory tuning
but not acceptable as a final immersed-solid formulation: the solid no-flux
condition must remain hard.  The sweep revealed this clearly through non-zero
`q6ImmersedSolidLeakProjectedFluxRmsLate` for strengths below one.

The current code now uses the following semantics:

- open fluid-fluid faces use `q6ProjectionStrength`;
- closed immersed-solid faces always apply the full no-flux correction;
- the same hard-wall rule is used for under-relaxed Q9 mass-flux corrections;
- therefore the immersed wall remains impermeable even for `q6ProjectionStrength
  < 1`.

With this correction, the most promising candidate to rerun is:

```text
Q9 hard-wall selected:
q6ProjectionStrength = 0.50
q9DensityRelaxationBeta = 0.00100
q9LowKMaxIndex = 2
```

This setting gave the best pre-correction compromise between population
reliability and organized recirculation, but must be rerun with the hard-wall
semantics before being accepted as a default.

## Q6/Q9 versus complete Q6/Q9/virial closure

The next validation step is a focused two-case comparison on the same immersed
step:

1. selected Q6/Q9, no virial kick;
2. selected Q6/Q9 plus virial EOS pressure kick.

The script `scripts/run_backward_step_liquid_closure_comparison.sh` generates
and runs both cases.  The virial module now uses the immersed-solid mask for its
pressure maps and gradients, so empty cells inside the solid rectangle do not
act as a spurious low-density liquid.  This is essential before testing the full
liquid closure on an immersed geometry.

Default liquid-closure comparison parameters:

```text
q6ProjectionStrength = 0.50
q9DensityRelaxationBeta = 0.00100
q9LowKMaxIndex = 2
Kvirial = 0.50
virialBeta = 0.05
```

Run:

```bash
./scripts/run_backward_step_liquid_closure_comparison.sh
```

Analyze from `matlab/`:

```matlab
suite = validate_backward_step_liquid_closure_comparison();
```

Primary acceptance checks:

- `q6ImmersedSolidLeakProjectedFluxRmsLate = 0`;
- `q9ImmersedSolidLeakMassFluxRmsLate = 0`;
- population reliability in the reversed zone remains comparable to Q9 without
  virial;
- `virialDuOverThermalRmsLate` remains small enough that the EOS kick is a
  liquid closure correction, not the dominant dynamics;
- low-k vorticity fraction and largest reversed component are not degraded.
