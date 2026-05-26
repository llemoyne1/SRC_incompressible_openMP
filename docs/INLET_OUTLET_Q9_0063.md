# 0063 — Minimal Q9 inlet/outlet support

This patch extends the 0062 open-channel path from Q6 to Q9, without enabling
virial/liquid EOS open boundaries yet.

Scope:

- supported: `classic`, `q6`, `q9` with one inlet/outlet axis and the transverse
  direction periodic or solid-wall paired;
- still rejected: `q9_virial`, `virialDiagnosticsEnable=true`,
  `virialKickEnable=true`, and immersed solids combined with open boundaries;
- no FFT path is introduced; Q9 still uses the generic elliptic face-field core
  and the existing elliptic low-pass filter.

For Q9, the open face prescription uses the compact mass-flux convention already
used by the adapter:

```text
baseMassFlux = cellMass * cellVelocity
```

Thus an inlet velocity `Uin` is converted into a prescribed mass flux

```text
Jin = meanCellMass * Uin
```

and the same balanced value is imposed on the inlet and outlet external faces of
the open axis. This mirrors the 0062 Q6 policy, but in mass-flux units. It is a
minimal, stable policy for the first Q9 open-channel smoke tests, not yet a
natural/outflow outlet model.

The reference smoke case is:

```text
examples/params_open_channel_q9_inlet_outlet_keepmean_64x32.kv
```

Run it with:

```bash
./scripts/run_open_channel_q9_inlet_outlet_smoke.sh
```

Expected diagnostics on the smoke case:

- `Np` and `totalMass` constant;
- `meanVx` maintained by `keepMeanFlowEnable=true`;
- `q6Applied=1`, `q6Converged=1`;
- `q9Applied=1`, `q9Converged=1`;
- `q9OpenBoundaryEnabled=1`;
- `q9OpenBoundaryMassFluxXLow ~= q9DensityMean * inletUxLeft`;
- `q9OpenBoundaryMassFluxXHigh ~= q9DensityMean * inletUxLeft`;
- `q9OpenBoundaryMassFluxBalance ~= 0`.

This is a numerical smoke test before physical validation. The next open-boundary
steps are natural outlet variants and virial/reservoir regularisation.
