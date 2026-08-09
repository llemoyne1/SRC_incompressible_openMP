# 0493x7e — combined x6g gas-interface pressure + x7d density relaxation

0493x7e is a qualification-only composition patch.  It changes no CUDA
operator.  The current resident Q6 RHS already assembles the two contributions
additively in the same `q6_build_independent_rhs_after_mask_0493w5` launch:

```
rhs = -div(u*)
    + x6g interface Dirichlet contribution from p_g - p_ref
    + x7d bulk density-relaxation target divergence
```

This is the desired separation of roles:

- x6g acts only through prepared alpha=0.5 interface-face Dirichlet data;
- x7d acts only in the qualified liquid bulk through
  `div(u)_target = (rawFill - 1)/tau_rho`;
- both reuse the same x6f pressure mask/stencil and the same CG solve;
- B1 remains the particle application path;
- explicit x7b virial density kick stays disabled.

No source change is needed to combine x6g and x7d.  0493x7e therefore adds a
single qualification runner and a compact cross-audit analyzer.

## Qualification sequence

Run:

```
LIVE_PROGRESS=1 bash scripts/run_0493x7e_x6g_x7d_validation.sh
```

The runner first reuses the already-qualified x6g three-case invariant suite,
but with x7d active at `tau_rho=0.25` and B1 enabled:

1. x6f `pGamma=0` reference + x7d;
2. x6g EOS with scale=0 + x7d, requiring strict null-path state equivalence;
3. x6g constant-pressure gauge case + x7d, using the existing gauge tolerances.

It then repeats the already-qualified x7d coarse/fine operator-refinement
scenario with x6g EOS pressure active in both grids:

- coarse: 300x150, dt=0.005, 100 steps by default;
- fine: 600x300, dt=0.0025, 200 steps by default;
- both: tau_rho=0.25, same seed and same physical time;
- gas-pressure reference is recomputed per grid from the initial uniform gas EOS.

The existing x6c, x6f, x6g and x7d analyzers are reused.  The new x7e analyzer
also verifies that the same run contains both a positive density-relaxation
coefficient/time and an enabled EOS interface-pressure audit on matching steps.

Set `COARSE_STEPS=500` to repeat the longer 500/1000-step combined comparison.
The runner is intentionally non-destructive outside its dedicated run root.
