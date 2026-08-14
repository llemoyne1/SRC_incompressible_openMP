# 0493x8c temporary stage-resolved momentum diagnostic

This x8c is deliberately disposable.

- It modifies only `src/src_mpcd_base.cpp`.
- No solver/kernel/parameter schema is changed.
- Gate is OFF by default.
- Installer creates an exact checked backup.
- Remover restores that exact source after the short diagnostic campaign.
- Long run is only 200 steps at 750x200.
- Momentum is sampled every 20 steps, not every step.
- Analyzer uses only Python standard library: no pandas/numpy/scipy/matplotlib.

Eight sampled states:
1. step_start
2. after_q6_prestream
3. after_force_stream
4. after_boundary
5. after_collision
6. after_q6_post
7. after_thermostat
8. after_darcy_post

x8a exact Darcy is reused rather than reimplemented. This lets the analyzer
split the Q6GF combined prestream interval into exact Darcy + body + Q6GF.

The purpose is localization only: Q6, stream/wall, boundary, collision,
thermostat, Darcy, or unassigned. x8a remains the cumulative budget authority.
