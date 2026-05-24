# 0064 — Virial EOS/kick with inlet/outlet

This patch enables the existing virial EOS diagnostic/kick path for open-channel
runs, after the 0062 Q6 and 0063 Q9 inlet/outlet flux conditions.

Scope:

- supported: clean open channel with one inlet/outlet axis and solid walls on the transverse axis;
- supported: `method=q9_virial` or `method=q9` with `virialDiagnosticsEnable=true` / `virialKickEnable=true`;
- still out of scope: immersed solids with inlet/outlet, von Karman strict validation, moving immersed solids.

The particle boundary remains the 0061b CUDA-like recycling inlet/outlet. Q6 and
Q9 still use the generic elliptic operator. No FFT path is added.

## Reservoir/bulk separation

The new parameter

```kv
virialOpenBoundaryExclusionCells = 3
```

marks the first/last cells adjacent to an inlet/outlet face as inactive for the
virial EOS and virial kick. These cells represent the particle reservoir/slab,
where density is deliberately controlled by recycling rather than by the bulk
liquid closure. The virial diagnostic/kick is therefore applied only in the
interior bulk.

The CSV now reports:

```text
virialOpenBoundaryExcludedCells
virialActiveCells
```

For the 64 x 32 reference case with a left/right inlet/outlet pair and an
exclusion of three cells at both ends, the expected counts are:

```text
excluded = 2 * 3 * 32 = 192
active   = 64 * 32 - 192 = 1856
```

## Reference smoke

```bash
./scripts/run_open_channel_q9_virial_inlet_outlet_smoke.sh
```

MATLAB analysis:

```matlab
cd matlab
T = analyze_open_channel_q9_virial_inlet_outlet_smoke('root','..');
cd ..
```

Expected qualitative checks:

- `Np` and `totalMass` remain constant;
- `meanVx` remains at the keep-mean target in this short smoke;
- Q6 and Q9 are applied and converged;
- `virialKickApplied=1`;
- excluded/active virial cells match the bulk/reservoir split;
- `kBTEstimate` remains close to the target;
- virial kick amplitudes remain small relative to the thermal velocity.
