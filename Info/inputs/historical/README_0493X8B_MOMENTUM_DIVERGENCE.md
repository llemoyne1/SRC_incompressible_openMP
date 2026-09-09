# 0493x8b — time-resolved momentum divergence

Offline-only analysis of the three completed 0493x8a 750x200 runs.

It reconstructs, on every common summary/diagnostic interval,

    Delta P = I_body + I_Darcy_exact + I_nonDarcyResidual

and compares:

- Q6-g-f minus Q6 (primary causal comparison);
- Q6 minus SRC (control comparison).

All reported "sink" quantities are positive when +x momentum is lost.

The primary onset diagnostic does **not** use an arbitrary absolute threshold.
For each cumulative excess component it reports the first sustained time at
which 10%, 25%, 50%, 75%, and 90% of that component's own final signed excess
has accumulated.  This makes it possible to ask whether the GF-Q6 difference
appears earlier in exact Darcy or in the non-Darcy residual.

Three consecutive sampled points are required by default (`--sustain-points 3`)
to reject one-point crossings.

The residual is deliberately kept named `non-Darcy residual`; it is not yet
assigned to Q6, walls, collision, thermostat, or streaming.

Main output files:

- `vk_momentum_GF_minus_Q6_timeseries_0493x8b.csv`
- `vk_momentum_Q6_minus_SRC_timeseries_0493x8b.csv`
- `vk_momentum_crossing_times_0493x8b.csv`
- `vk_momentum_window_contributions_0493x8b.csv`
- `vk_momentum_final_attribution_0493x8b.csv`
- PNG plots for global velocity, cumulative budgets, and interval differences.
